# typed: true
# frozen_string_literal: true

# Decorator for a Vulnerability object and associated VulnerableVersionRanges
# which acts a read-only shim between database models and the public API
class SecurityAdvisory < Vulnerability
  include GitHub::Relay::GlobalIdentification
  include HasCVEUrl
  include GitHub::Memoizer # appease Sorbet


  DEFAULT_COLLECTION_ORDER = { "field" => "id", "direction" => "DESC" }

  has_many :vulnerabilities, class_name: "SecurityVulnerability",
                             foreign_key: :vulnerability_id,
                             inverse_of: :security_advisory

  # SecurityAdvisory model is used as the notification thread for the newsies SecurityAdvisoryNotification
  # Newsies requires all thread objects to implement the notifications_list method (to allow them to be marked as read etc...)
  # In the case of the SecurityAdvisoryNotification, the notifications_list is the user viewing the notification
  # But since the user viewing the notification is not a field we know of in advance, we need to make notifications_list
  # an accessor method so we can set/read it on the  fly.
  attr_accessor :notifications_list

  def global_id
    ghsa_id
  end

  def summary(atom: false)
    if read_attribute(:summary).present?
      read_attribute(:summary)
    elsif severity.present? & affected(atom: atom).present?
      "#{T.must(severity).capitalize} severity vulnerability that affects #{affected(atom: atom).to_sentence}"
    else
      description.truncate(100)
    end
  end

  # When we are rendering the summary for advisories in the ATOM feed, we
  # utilize the memoized public_vulnerabilities method below to ensure we aren't making
  # extra VulnerableVersionRange queries (what advisory.affects does) when we already have loaded
  # SecurityVulnerabilites. Used in feed only since this loading is a no-no in GraphQL.
  def affected(atom: false)
    if GitHub.flipper[:advisories_atom_decrease_queries].enabled? && atom
      public_vulnerabilities.pluck(:affects).sort.uniq
    else
      affects
    end
  end

  def references
    reference_urls.map { |url| { url: url } }
  end

  def primary_reference
    references.first&.fetch(:url)
  end

  # Iterate over the SecurityVulnerabilites we already have loaded to avoid making an extra
  # VulnerableVersionRange query. Mimics `Vulnerability#public_vulnerable_version_ranges`
  memoize def public_vulnerabilities
    vulnerabilities.select(&:has_public_ecosystem?)
  end

  def matches_ecosystem?(ecosystem = nil)
    return true if ecosystem.nil?

    vulnerable_version_ranges.any? do |vulnerable_version_range|
      vulnerable_version_range.ecosystem && T.must(vulnerable_version_range.ecosystem).downcase == ecosystem.downcase
    end
  end

  def matches_severities?(severities = [])
    return true if severities.nil? || severities.empty?

    severities.include?(T.must(severity).downcase)
  end

  def hydro_entity_payload(overrides: {})
    {
      ghsa_id: ghsa_id,
      cve_id: cve_id,
      severity: Hydro::EntitySerializer.enum_from_string(severity),
      status: status,
      published_at: published_at,
      updated_at: updated_at,
      withdrawn_at: withdrawn_at,
    }
  end

  def notifications_permalink
    UrlHelpers.global_advisory_dependabot_alerts_url(host: GitHub.url, id: ghsa_id)
  end

  def notifications_thread
    self
  end
end
