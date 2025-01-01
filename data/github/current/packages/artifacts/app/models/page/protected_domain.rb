# typed: false
# frozen_string_literal: true

require "github/pages/dns_resolver"

class Page::ProtectedDomain < ApplicationRecord::Domain::Repositories
  self.table_name = :pages_protected_domains

  include Instrumentation::Model
  include PagesHelper

  belongs_to :owner, polymorphic: true

  validates_presence_of :owner, :name
  validate :validate_name
  validates_uniqueness_of :name, scope: :owner, message: "has already been added"
  before_save :generate_verification_code, if: :new_record?
  before_save :generate_parent_domain, if: :new_record?

  after_create_commit :instrument_create
  after_update_commit :manage_custom_domain_routing
  after_destroy_commit :instrument_destroy, :cleanup_pages

  enum :state, { unverified: 0, pending: 1, verified: 2 }, default: :unverified

  # Public: Indicates the starting period by which we should verify existing, verified domains.
  VERIFICATION_SCAN_GRACE_DURATION = 7.days.freeze

  # Public: Number of days allowed before the domain is to move into an unverified state
  DAYS_UNTIL_UNVERIFIED_GRACE_DURATION = 7.days.freeze

  # Internal: Returns the ProtectedDomains that should be included in the next verification scan.
  #
  # Returns: Enumeration of ProtectedDomain objects with only their ID attributes set.
  scope :for_verification_scan, -> {
    select(:id).verified.where("last_verified_at <= ?", VERIFICATION_SCAN_GRACE_DURATION.ago)
  }

  # Internal: Query used by Pages::ProcessPendingDomainsJob which determines whether or not a pending domain
  # should ultimately be unverified.
  #
  # Returns: Enumeration of ProtectedDomain objects with only their ID attributes set.
  scope :for_pending_verification_scan, -> {
    select(:id).pending.where("unverified_at <= ? OR unverified_at is NULL", Time.current)
  }

  def to_param
    name
  end

  # Public: Verify the domain by checking if the DNS contains a TXT record
  # No matter the current state of the domain in the DB, the DNS is
  # always checked to see if the TXT record is present. If the record
  # is present the state is set to :verified. If this call is made on
  # a verified domain but the TXT record is not found, the domain goes
  # into pending state. Now the domain will get a grace period of 7 days
  # to prove ownership. unverified_at tracks the grace period end time
  #
  # Returns: Boolean
  def verify
    verify_status = check_dns_txt_record_exists?

    case verify_status
    when :verified
      unless self.verified?
        self.verified!
      end
    when :dns_record_not_found, :no_domain
      if self.verified?
        self.pending!
      elsif self.pending?
        self.process_verification_result_for_pending
      end
      errors.add(:base, "We couldn't find the TXT record. Note that DNS changes can take up to 24 hours.")
    when :resolve_error
      errors.add(:base, "We couldn't find the TXT record. If it was recently added, wait a few moments before trying again. Note that it may take up to 24 hours for DNS changes to take effect globally.")
    when :dns_error
      errors.add(:base, "An error occurred while verifying this DNS record.")
    else
      raise ArgumentError.new("Unrecognized `Page::ProtectedDomain#check_dns_txt_record_exists?` return value: #{verify_status.inspect}")
    end

    instrument_verify(verify_status)
    verify_status == :verified
  end

  # Public: Sets state to verified and sets last_verified_at to the current time.
  def verified!
    self.unverified_at = nil
    self.last_verified_at = Time.current
    GitHub.logger.info(
      "code.namespace" => "github.pages.protected_domain",
      "code.function" => :verified!,
      "gh.pages.protected_domain.id" => self.id,
      "gh.pages.protected_domain" => self.name
    )
    instrument_status_change
    super
  end

  # Public: Sets state to pending and sets unverified_at to a date in the future as determined by DAYS_UNTIL_UNVERIFIED_GRACE_DURATION
  def pending!
    self.unverified_at = DAYS_UNTIL_UNVERIFIED_GRACE_DURATION.from_now
    GitHub.logger.info(
      "code.namespace" => "github.pages.protected_domain",
      "code.function" => :pending!,
      "gh.pages.protected_domain.id" => self.id,
      "gh.pages.protected_domain" => self.name
    )
    instrument_status_change
    super
  end

  # Public: Sets state to unverified and clears unverified_at
  def unverified!
    self.unverified_at = nil
    GitHub.logger.info(
      "code.namespace" => "github.pages.protected_domain",
      "code.function" => :unverified!,
      "gh.pages.protected_domain.id" => self.id,
      "gh.pages.protected_domain" => self.name
    )
    instrument_status_change
    super
  end

  def check_dns_txt_record_exists?
    resolver = GitHub::Pages::DnsResolver.new
    result = resolver.verify_challenge(challenge_key: dns_txt_key, expected_token: challenge)

    return :verified if result.success?

    return :dns_record_not_found if result.error!.is_a?(GitHub::Pages::DnsResolver::TokenNotFoundError)
    return :no_domain if result.error!.is_a?(GitHub::Pages::DnsResolver::MissingChallengeKeyError)
    return :resolve_error if result.error!.is_a?(GitHub::Pages::DnsResolver::DnsRequestError)
    :dns_error
  end

  def github_io_suffix_present?(name)
    (name || "").downcase.strip.split(".")[-2..-1] == %w(github io)
  end

  def generate_verification_code
    return true if challenge.present?

    token = SecureRandom.hex(15)
    self.challenge = token
    true
  end

  def generate_parent_domain
    return true if self.parent_domain.present?

    begin
      self.parent_domain = self.class.parent_domain_of(self.name)
    rescue PublicSuffix::DomainInvalid
      errors.add(:domain, "is not a valid subdomain or second-level domain")
      return false
    end

    true
  end

  def async_dns_txt_key
    async_owner.then do |_owner|
      dns_txt_key
    end
  end

  def dns_txt_key
    "_github-pages-challenge-#{owner.to_param}.#{punycode_encoded_domain}"
  end

  def dns_txt_key_copy_challenge
    "_github-pages-challenge-#{owner.to_param}.#{PublicSuffix.parse(name).trd}".chomp(".")
  end

  def domain_string_for_challenge
    PublicSuffix.parse(name).domain
  end

  def punycode_encoded_domain
    Addressable::IDNA.to_ascii(name)
  end

  def validate_name
    # Valid public domain (i.e. on a public suffix)
    if name && name.present? && !PublicSuffix.valid?(name)
      errors.add(:domain, "is not a valid public domain.")
    end

    # Not a www variant
    if name && name.strip.start_with?("www.")
      errors.add(:domain, "cannot start with a 'www' prefix. Verify your root domain instead.")
    end

    # Not a homograph
    if Page::ProtectedDomain.homograph?(name)
      errors.add(:domain, "is not eligible for verification, as it is a potential homograph.")
    end

    # Not a github.io domain
    if github_io_suffix_present?(name)
      errors.add(:domain, "cannot end with github.io.")
    end

    # Invalid url format
    if invalid_format_present?(name)
      errors.add(:domain, "is not properly formatted.")
    end

    # Ip address detected
    if ip_present?(name)
      errors.add(:domain, "cannot be an ip address.")
    end
  end

  def invalid_format_present?(name)
    has_improper_format = name.strip !~ /\A[\w][\w\-\.]+[\w\-]\z/ || !name.include?(".")
  end

  def ip_present?(name)
    ip_address_present = name =~ /\A\d+\.\d+\.\d+\.\d+\z/ || name.include?(":")
  end

  def current_state
    state.to_sym
  end

  def cleanup_pages
    # When a domain protection is deleted and was in verified or pending state, trigger the
    # background logic that will disassociate Pages from their custom domain if needed.
    if state == "verified" || state == "pending"
      Pages::DeleteProtectedDomainJob.perform_later(domain_name: name, owner: owner)
    end
  end

  # Utility: Parses the passed domain string to determine the domain that it
  # is a subdomain of (or "parent" domain). Validation is performed to ensure
  # the returned domain does not match any entries on the Public Suffix list.
  #
  # domain - a standard domain name (with no trailing dot)
  #
  # Returns a string when valid input is given or nil when passed a top-level
  # domain.
  def self.parent_domain_of(domain)
    begin
      d = PublicSuffix.parse(domain)
      return nil if d.domain == domain

      parts = domain.split(".")
      joined = parts[1..].join(".")

      return d.domain if joined == d.tld
      return joined
    rescue PublicSuffix::Error
      return nil
    end unless domain.nil?
    nil
  end

  def self.default_event_prefix
    :pages_protected_domain
  end

  # Return a boolean indicating if a domain is currently protected directly
  # or indirectly (e.g. test.domain.com may be protected via domain.com).
  # The protected status only look at verified and pending states.
  def self.protected?(domain, parent_domain)
    Page::ProtectedDomain
      .where(name: domain)
      .or(Page::ProtectedDomain.where(name: parent_domain))
      .and(Page::ProtectedDomain.where(state: %w[verified pending])).exists?
  end

  # Return a boolean indicating if a domain is a homograph one.
  def self.homograph?(domain)
    return true if domain && HomographDetector.homograph_attack?("http://" + Addressable::IDNA.to_unicode(domain))
    false
  end

  def self.overlapping_protected_domains(domain_name)
    parent_domain = parent_domain_of(domain_name)
    Page::ProtectedDomain
      .where(name: [domain_name, parent_domain])
      .or(Page::ProtectedDomain.where(parent_domain: domain_name))
      .and(Page::ProtectedDomain.where(state: "verified"))
  end

  private

  # Internal: Unsets the `cname` and `parent_domain` columns on the `pages` table
  # when this record prevents them from having this custom domain. When a protected
  # domain transitions to `unverified` or `verified`, pages that have an exact
  # match or parent domain match (subdomains of this protected domain) are
  # updated accordingly.
  def manage_custom_domain_routing
    return true if GitHub.enterprise?

    if saved_change_to_state?(to: "unverified")
      Pages::DeleteProtectedDomainJob.perform_later(domain_name: name, owner: owner)
    elsif saved_change_to_state?(to: "verified")
      Pages::ClearMatchingPageCnamesJob.perform_later(protected_domain: self)
    end

    true
  end

  # Private: Get the default nameservers detected by Resolv, filtering out any
  # that we never want to use.
  #
  # Returns Array of String
  def default_nameservers
    return @default_nameservers if defined? @default_nameservers

    @default_nameservers = filter_invalid_nameservers(Resolv::DNS::Config.default_config_hash[:nameserver])
  end

  # Private: Filter invalid nameservers out of the a given Array of nameservers.
  #
  # Filter out any IPv6 link-local addresses from nameservers (for example
  # "fe80::5cb0:3cff:fe51:29b0%eth0"), as they cause a major bug when used
  # for DNS queries with Resolv.
  #
  # More details in https://github.com/github/admin-experience/issues/1255
  #
  # Returns Array of String
  def filter_invalid_nameservers(nameservers)
    return [] unless nameservers.present?
    flitered_ns = nameservers.reject do |ns|
      ns =~ /\A.*\%[a-zA-Z0-9]*\z/
    end

    rejected_ns = nameservers - flitered_ns
    errors.add(base: "invalid nameservers found #{rejected_ns}") if !rejected_ns.empty?

    flitered_ns
  end

  # Private: Use the GitHub.default_request_timeout as the DNS query timeout value in seconds.
  # Set the timeout to be half a second shorter than the request timeout, so
  # there's time for Resolv::ResolvTimeout timeout to get raised and rescued.
  #
  # Returns Float
  def dns_timeout
    GitHub.default_request_timeout - 0.5
  end

  def instrument_create
    GitHub.dogstats.increment "pages.protected_domain.create",
                  tags: ["owner_type:#{self.owner_type}", "state:#{self.state}"]

    instrument :create, owner: owner.name, owner_type: self.owner_type, domain: name, state: self.state, org_id: owner.organization? ? owner.id : nil
    GlobalInstrumenter.instrument("protected_domain.create", {
      domain: self,
      owner: owner
    })
  end

  def instrument_destroy
    GitHub.dogstats.increment "pages.protected_domain.delete",
           tags: ["owner_type:#{self.owner_type}", "state:#{self.state}"]

    instrument :delete, owner: owner.name, owner_type: self.owner_type, domain: name, state: self.state, org_id: owner.organization? ? owner.id : nil
    GlobalInstrumenter.instrument("protected_domain.delete", {
      domain: self,
      owner: owner
    })
  end

  def instrument_status_change
    GlobalInstrumenter.instrument("protected_domain.#{self.state}", {
      domain: self,
      user: owner
    })
  end

  def instrument_verify(verify_status)
    GitHub.dogstats.increment "pages.protected_domain.verify",
           tags: ["owner_type:#{self.owner_type}", "current_state:#{self.state}", "verify_status_code:#{verify_status}"]

    instrument :verify, owner: owner.name, owner_type: self.owner_type, domain: self.name, state: self.state, org_id: owner.organization? ? owner.id : nil

    GlobalInstrumenter.instrument("protected_domain.verify_attempt", {
      domain: self,
      user: owner,
      verify_status: verify_status
    })
  end

  def target_for_conditional_access
    owner
  end

  def process_verification_result_for_pending
    if unverified_at.nil?
      # Call pending mutator to reset grace period
      pending!
    elsif unverified_at.past?
      unverified!
    end
  end
end
