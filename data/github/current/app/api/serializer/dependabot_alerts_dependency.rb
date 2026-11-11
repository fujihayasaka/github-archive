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
      :assignees,
      { repository: [:owner, :network] },
      { vulnerability: [:cwe_references, :vulnerability_references, :cwes] },
      { vulnerable_version_range: :vulnerability },
    ])

    GitHub::PrefillAssociations.prefill_batch_method(alerts.map(&:vulnerability), :cve_epss)
    GitHub::PrefillAssociations.prefill_batch_method(alerts, :current_dismissal_request)

    # Preload advisories for SecurityAdvisory Rails STI
    prefill_advisories = alerts.filter_map { |alert| alert.vulnerability&.becomes(SecurityAdvisory) }
    GitHub::PrefillAssociations.prefill_associations(prefill_advisories, [
      :cwe_references, :vulnerability_references, :cwes, :cve_epss,
      { vulnerabilities: :vulnerability }
    ])
    GitHub::PrefillAssociations.prefill_associations(prefill_advisories, [:vulnerable_version_ranges])
    GitHub::PrefillAssociations.prefill_batch_method(prefill_advisories, :cve_epss)

    alerts.map do |alert|
      dependabot_alert_hash(
        alert,
        options.merge(available_records: prefill_advisories),
      )
    end
  end

  sig { params(alert: T.nilable(RepositoryVulnerabilityAlert), options: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def dependabot_alert_hash(alert, options)
    return nil unless alert&.active?

    repository = T.must(alert.repository)
    owner = repository.owner
    business = repository.business

    flag_actors = T.let([repository, options[:current_user]], T::Array[GitHub::VexiActor])
    flag_actors << owner if owner
    flag_actors << business if business
    include_innersource = !GitHub.enterprise? && FeatureFlag.vexi.enabled?(:innersource_alerting, flag_actors, default: false)

    return nil if alert.vulnerability&.innersource? && !include_innersource

    security_options = options.merge(
      use_medium_severity: true,
      available_records: options[:available_records],
      include_classification: true,
      use_unknown_severity: true
    )

    vulnerability = alert.vulnerability

    hash = {
      number: alert.number,
      state: alert.state,
      dependency: dependabot_alert_dependency_hash(alert),
      security_advisory: security_advisory_hash(alert.vulnerability, security_options),
      security_vulnerability: security_vulnerability_hash(alert.vulnerable_version_range, security_options),
      url: url("/repos/#{repository.name_with_owner_for_api(use: options[:serialize_login])}/dependabot/alerts/#{alert.number}"),
      html_url: html_url("/#{repository.name_with_owner_for_api(use: options[:serialize_login])}/security/dependabot/#{alert.number}"),
      created_at: time(alert.created_at),
      updated_at: time(alert.last_state_change_at),
      dismissal_request: dependabot_alert_dismissal_request_info(alert, repository),
      assignees: alert.assignees.map { |u| simple_user_hash(u, options) },
    }

    if vulnerability&.innersource?
      hash[:visibility_scope] = vulnerability.visibility
      hash[:external_id] = vulnerability.external_id
    end

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
      # This attribute is not available in GHES until Dependency Graph Platform is available there
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

  # Serializes the current dismissal request for a Dependabot alert, if one exists.
  # Expects current_dismissal_request to be prefilled via prefill_batch_method.
  def dependabot_alert_dismissal_request_info(alert, repository)
    dismissal_request = alert.current_dismissal_request

    return nil unless dismissal_request

    # Don't show expired requests - they're no longer actionable
    return nil if dismissal_request.expired?

    # Compute the current status
    status = case dismissal_request.status
    when "approved", "rejected", "cancelled"
      dismissal_request.status
    else
      # For pending requests, compute current evaluation status (pending/approved/rejected)
      dismissal_request.compute_status.serialize
    end

    {
      id: dismissal_request.id,
      status: status,
      requester: {
        id: dismissal_request.requester&.id,
        login: dismissal_request.requester&.display_login,
      },
      created_at: time(dismissal_request.created_at),
      url: url("/repos/#{repository.name_with_display_owner}/dismissal-requests/dependabot/#{alert.number}"),
    }
  end
end
