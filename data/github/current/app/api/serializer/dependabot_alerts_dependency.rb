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

    # Prefetch dismissal requests for all alerts to avoid N+1 queries
    dismissal_requests_by_alert = prefetch_dismissal_requests(alerts)

    alerts.map do |alert|
      dependabot_alert_hash(
        alert,
        options.merge(available_records: prefill_advisories),
        dismissal_requests_by_alert: dismissal_requests_by_alert
      )
    end
  end

  def dependabot_alert_hash(alert, options, dismissal_requests_by_alert: nil)
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

    # Add dismissal request info if delegated closures are enabled
    if Dependabot::SecurityProduct::DelegatedClosures.dependabot_alert_dismissal_requests_for?(repository)
      hash[:dismissal_request] = dependabot_alert_dismissal_request_info(alert, repository, dismissal_requests_by_alert)
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

  # Prefetch dismissal requests for all alerts to avoid N+1 queries
  # Returns a hash mapping "repo_id:alert_number" to the dismissal request
  def prefetch_dismissal_requests(alerts)
    return {} if alerts.empty?

    # Group alerts by repository to check feature flag per repo
    alerts_by_repo = alerts.group_by(&:repository)
    enabled_repos = alerts_by_repo.keys.select do |repo|
      Dependabot::SecurityProduct::DelegatedClosures.dependabot_alert_dismissal_requests_for?(repo)
    end
    enabled_repo_ids = enabled_repos.map(&:id)

    return {} if enabled_repo_ids.empty?

    # Get alert numbers for enabled repos
    alert_identifiers = alerts.select { |a| enabled_repo_ids.include?(a.repository_id) }
                              .map { |a| [a.repository_id, a.number.to_s] }

    return {} if alert_identifiers.empty?

    # Batch query for all dismissal requests
    # We need to find the most recent active request for each alert
    # Exclude cancelled and completed requests (completed means the alert was already dismissed)
    requests = Exemptions::ExemptionRequest
      .where(repository_id: enabled_repo_ids)
      .where(request_type: Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE)
      .where(resource_identifier: alert_identifiers.map(&:last).uniq)
      .where.not(status: %w[cancelled completed])
      .includes(:requester)
      .order(created_at: :desc)

    # Group by repo_id and resource_identifier, keeping only the most recent
    requests.each_with_object({}) do |request, hash|
      key = "#{request.repository_id}:#{request.resource_identifier}"
      hash[key] ||= request # First one is most recent due to ordering
    end
  end

  # Returns dismissal request info for a Dependabot alert, if one exists
  def dependabot_alert_dismissal_request_info(alert, repository, prefetched_requests = nil)
    # Use prefetched data if available, otherwise query directly (for single alert fetches)
    dismissal_request = if prefetched_requests
      prefetched_requests["#{repository.id}:#{alert.number}"]
    else
      # Find the most recent active dismissal request for this alert
      # Exclude cancelled and completed requests
      Exemptions::ExemptionRequest
        .where(
          repository_id: repository.id,
          request_type: Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE,
          resource_identifier: alert.number.to_s
        )
        .where.not(status: %w[cancelled completed])
        .order(created_at: :desc)
        .first
    end

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
