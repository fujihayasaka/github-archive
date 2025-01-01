# typed: true
# frozen_string_literal: true

module Api::App::DependabotAlertsHelpers
  extend T::Helpers

  requires_ancestor { ::Api::App }

  include GitHub::SecurityCenter::TenantFilteringHelper

  REPO_ARCHIVED_MESSAGE = "Dependabot alerts are not available for archived repositories."
  INSTANCE_DISABLED_MESSAGE = "Dependabot alerts are disabled. Contact your GitHub Enterprise site administrator for assistance."
  DEPENDENCY_GRAPH_DISABLED_MESSAGE = "Dependency Graph is disabled. Contact your GitHub Enterprise site administrator for assistance."
  REPO_DISABLED_MESSAGE = "Dependabot alerts are disabled for this repository."

  STATE_CHANGE_COMMENT_MAX_LENGTH = 280

  DEFAULT_CURSOR_PAGINATION_RESULT_SIZE = 30

  def ensure_repo_access_and_dependabot_alerts_enabled!(repo)
    unless alerts_requested_by_site_admin?
      can_read_repo =
        access_allowed? :v4_get_repo,
          resource: repo,
          repo: repo,
          allow_integrations: true,
          allow_user_via_granular_actor: true

      unless can_read_repo
        # for public repos we can expose its existance with a 403 Forbidden error message
        # for private repos we need to hide its existance
        if repo.public?
          deliver_error!(403)
        else
          deliver_error!(404)
        end
      end
    end

    deliver_error!(403, message: REPO_ARCHIVED_MESSAGE) if repo.archived?
    deliver_error!(403, message: INSTANCE_DISABLED_MESSAGE) unless SecurityProduct::VulnerabilityAlerts.enabled_for_instance?
    deliver_error!(403, message: DEPENDENCY_GRAPH_DISABLED_MESSAGE) unless GitHub.dependency_graph_enabled?
    deliver_error!(403, message: REPO_DISABLED_MESSAGE) unless repo.vulnerability_alerts_enabled?
  end

  def ensure_non_conflicting_cursor_params!
    if params.key?(:after) && params.key?(:before)
      deliver_error!(400, message: "Please do not provide both 'before' and 'after' parameters.")
    end
  end

  def normalize_comment(comment)
    return nil if comment.nil? || comment.empty?
    comment.encode("UTF-8", universal_newline: true)
  end

  def find_alert!(repo)
    number = int_id_param!(key: :alert_number, halt: true)
    alert = repo.repository_vulnerability_alerts.find_by(number: number)

    if alert.nil?
      deliver_error!(404, message: "No alert found for alert number #{number}")
    elsif alert.vulnerable_version_range.nil?
      deliver_error!(404, message: "Alert number #{number} has been withdrawn")
    end

    alert
  end

  def dismiss_alert(alert, data)
    if alert.state == "dismissed"
      deliver_error!(409, message: "Alert #{alert.number} is already dismissed")
    end

    if data["dismissed_reason"].nil?
      deliver_error!(400, message: "Setting an alert to 'dismissed' requires a 'dismissed_reason'")
    end

    reason = data["dismissed_reason"].to_sym
    data["dismissed_comment"] = normalize_comment(data["dismissed_comment"])

    alert.dismiss(actor: current_user, reason: reason, comment: data["dismissed_comment"])
  end

  def reopen_alert(alert, data)
    if alert.state == "open"
      deliver_error!(409, message: "Alert #{alert.number} is already open")
    end

    %w[dismissed_reason dismissed_comment].each do |dismissal_only_field|
      if data[dismissal_only_field]&.present?
        deliver_error!(400, message: "Can't set '#{dismissal_only_field}' when setting an alert to 'open'")
      end
    end
    alert.reopen(actor: current_user)
  end

  # We're reusing GraphQL logic here in order to implement cursor-based
  # pagination consistently.
  def get_cursor_paginated_alerts(alerts)
    before = params[:before].presence
    after = params[:after].presence
    per_page = params[:per_page].presence || DEFAULT_CURSOR_PAGINATION_RESULT_SIZE

    # if neither first or last is set, we default to the first per_page items
    first = !params[:first].presence && !params[:last].presence ? per_page : params[:first].presence
    last = params[:last].presence

    # if per_page is used with before, we need to reset first param to what is passed in
    if params.key?(:before) && params.key?(:per_page)
      last = per_page
      first = params[:first].presence
    elsif params.key?(:after) && params.key?(:per_page)
      first = per_page
    end

    first = first.to_i if first
    last = last.to_i if last

    alerts_platform_relation = Platform::ConnectionWrappers::Relation.new(
      alerts,
      before: before,
      after: after,
      first: first,
      last: last,
    )

    [alerts_platform_relation.edge_nodes.sync, alerts_platform_relation]
  end

  def set_cursor_based_pagination_headers(page_info:, has_next_page:, has_previous_page:)
    if has_next_page
      @links.add_current({ after: page_info.end_cursor, before: nil, page: nil }, rel: "next")
    end

    if has_previous_page
      @links.add_current({ before: page_info.start_cursor, after: nil, page: nil }, rel: "prev")
    end
  end

  def alerts_for_repository(repository:, cursor_pagination:)
    alerts(repository: repository, cursor_pagination: cursor_pagination)
  end

  def alerts_for_organization(organization:, allowed_repository_ids:, cursor_pagination:)
    alerts(organization: organization, allowed_repository_ids: allowed_repository_ids, cursor_pagination: cursor_pagination)
  end

  def alerts_for_enterprise(business:, organization_ids:, cursor_pagination:)
    alerts(business: business, organization_ids: organization_ids, cursor_pagination: cursor_pagination)
  end

  def using_cursor_based_pagination?
    params.key?(:after) || params.key?(:before) || params.key?(:first) || params.key?(:last)
  end

  private

  def alerts(repository: nil, organization: nil, allowed_repository_ids: nil, business: nil, organization_ids: nil, cursor_pagination: true)
    query_string = params.
      slice(*Search::Queries::SecurityCenter::DependabotAlertsQuery::API_QUALIFIERS).
      map { |key, value| "#{key}:#{value}" }.
      join(" ")
    query_hash = Search::Queries::SecurityCenter::DependabotAlertsQuery.parse_and_normalize(query_string)
    sort = :"#{params[:sort] == "updated" ? "last_state_change_at" : "created"}_#{params[:direction] == "asc" ? "asc" : "desc"}"

    if repository
      query = RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(repository: repository)
    elsif organization
      organization.trigger_security_center_reconciliation
      query = RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(organization: organization, allowed_repository_ids: allowed_repository_ids, user: current_user)
    else
      business.trigger_security_center_reconciliation
      query = RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(business: business, organization_ids: organization_ids, user: current_user)
    end

    query = query.severities_are(query_hash[:severity]).
      packages_are(query_hash[:package]).
      ecosystems_are(query_hash[:ecosystem]).
      dependency_scopes_are(query_hash[:scope]).
      sort_by(sort)

    if repository.present? && query_hash[:manifest].present?
      query = query.manifests_are(query_hash[:manifest])
    end

    # Resolve the query above to an Active Record relation representing all
    # matching alerts. We haven't performed the database query yet and we'll
    # further filter these results below before we do.
    #
    # Ensure we force a JOIN on the Vulnerabilities table so that we don't error out
    # in the event that an alert's vulnerable version range was deleted (withdrawn).
    alerts = query.resolve(ignore_pagination: true, force_vulnerabilities_join: true)

    # Split the state query parameter into an array of strings and ignore any
    # invalid state values.
    #
    # We're not using the UngroupedAlertQuery's state querying ability here
    # because it only supports querying by a single open/closed value. In the
    # API, we want to support querying by multiple, specific states
    # (dismissed, fixed, etc.).
    #
    # We may decide to unify state querying across UI and API in the future.
    states = params[:state]&.split(",") & RepositoryVulnerabilityAlert.states.keys
    alerts = alerts.where(state: states) if states.present?

    if cursor_pagination
      alerts, alerts_platform_relation = get_cursor_paginated_alerts(alerts)

      set_cursor_based_pagination_headers(
        page_info: alerts_platform_relation.page_info,
        has_next_page: alerts_platform_relation.has_next_page,
        has_previous_page: alerts_platform_relation.has_previous_page,
      ) if alerts.any?
    else
      set_pagination_headers(collection_size: alerts.count)
      alerts = paginate_rel(alerts)
    end

    filtered_alerts, _ = filter_tenant_rows(
      query.tenant_filter_scope,
      alerts,
      -> (alert) { alert.repository_id }
    )

    filtered_alerts
  end

  def alerts_requested_by_site_admin?
    current_user&.site_admin? && env["REQUEST_METHOD"] == "GET"
  end
end
