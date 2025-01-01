# typed: true
# frozen_string_literal: true

module Api::Serializer::DependabotAlertsDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::RepositoriesDependency }
  requires_ancestor { Api::Serializer::SecurityAdvisoriesDependency }
  requires_ancestor { Api::Serializer::UserDependency }

  def dependabot_alerts_hash(data, options)
    alerts = data.fetch(:alerts, [])

    GitHub::PrefillAssociations.prefill_associations(alerts, [
      { repository: [:owner, :network] },
      { vulnerability: [:cwe_references, :vulnerability_references, :cwes] },
      { vulnerable_version_range: :vulnerability },
    ])

    GitHub::PrefillAssociations.prefill_batch_method(alerts.map(&:vulnerability), :cve_epss)

    # Preload advisories for SecurityAdvisory Rails STI
    prefill_advisories = alerts.map { |alert| alert.vulnerability.becomes(SecurityAdvisory) if alert.vulnerability.class == Vulnerability }.compact
    GitHub::PrefillAssociations.prefill_associations(prefill_advisories, [
      :cwe_references, :vulnerability_references, :cwes, :cve_epss,
      { vulnerabilities: :vulnerability }
    ])
    GitHub::PrefillAssociations.prefill_associations(prefill_advisories, [:vulnerable_version_ranges])
    GitHub::PrefillAssociations.prefill_batch_method(prefill_advisories, :cve_epss)

    alerts.map do |alert|
      dependabot_alert_hash(alert, options.merge(available_records: prefill_advisories))
    end
  end

  def dependabot_alert_hash(alert, options)
    return nil unless alert&.active?

    repository = alert.repository

    hash = {
      number: alert.number,
      state: alert.state,
      dependency: dependabot_alert_dependency_hash(alert),
      security_advisory: security_advisory_hash(alert.vulnerability, use_medium_severity: true, available_records: options[:available_records]),
      security_vulnerability: security_vulnerability_hash(alert.vulnerable_version_range, use_medium_severity: true, available_records: options[:available_records]),
      url: url("/repos/#{repository.name_with_owner_for_api(use: options[:serialize_login])}/dependabot/alerts/#{alert.number}"),
      html_url: html_url("/#{repository.name_with_owner_for_api(use: options[:serialize_login])}/security/dependabot/#{alert.number}"),
      created_at: time(alert.created_at),
      updated_at: time(alert.last_state_change_at),
    }

    hash.update(dependabot_alert_metadata_hash(alert, options))

    if options[:include_repository]
      hash[:repository] = simple_repository_hash(alert.repository, options)
    end

    hash
  end

  def dependabot_alert_dependency_hash(alert)
    {
      package: {
        ecosystem: alert.ecosystem.downcase,
        name: alert.package_name,
      },
      manifest_path: alert.vulnerable_manifest_path.presence,
      scope: alert.dependency_scope.presence,
    }.tap do |h|
      # This attribute is not available in GHES until further notice.
      h[:relationship] = alert.dependency_relationship.presence unless GitHub.enterprise?
    end
  end

  def dependabot_alert_metadata_hash(alert, options)
    if alert.dismissed?
      {
        dismissed_at: time(alert.last_state_change_at),
        dismissed_by: user_hash(alert.last_state_change_actor, content_options(options)) ||
                      simple_user_hash(User.ghost, content_options(options)),
        dismissed_reason: alert.last_state_change_reason,
        dismissed_comment: alert.last_state_change_comment.presence,
        fixed_at: nil,
        auto_dismissed_at: nil,
      }
    elsif alert.auto_dismissed?
      {
        dismissed_at: nil,
        dismissed_by: nil,
        dismissed_reason: nil,
        dismissed_comment: nil,
        fixed_at: nil,
        auto_dismissed_at: time(alert.last_state_change_at) || time(alert.created_at),
      }
    elsif alert.fixed?
      {
        dismissed_at: nil,
        dismissed_by: nil,
        dismissed_reason: nil,
        dismissed_comment: nil,
        fixed_at: time(alert.last_state_change_at),
        auto_dismissed_at: nil,
      }
    else
      {
        dismissed_at: nil,
        dismissed_by: nil,
        dismissed_reason: nil,
        dismissed_comment: nil,
        fixed_at: nil,
        auto_dismissed_at: nil,
      }
    end
  end
end
