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
    alerts_platform_relation = Platform::ConnectionWrappers::Relation.new(
      alerts,
      **cursor_pagination_params
    )

    [alerts_platform_relation.edge_nodes.sync, alerts_platform_relation]
  end

  def cursor_pagination_params
    before = params[:before].presence
    after = params[:after].presence
    per_page = params[:per_page].presence || DEFAULT_CURSOR_PAGINATION_RESULT_SIZE

    # Map per_page to first or last depending on whether the before key is set or not.
    # Platform::ConnectionWrappers::Relation expects first or last to be set, not per_page.
    if params.key?(:before)
      first = nil
      last = per_page
    else
      first = per_page
      last = nil
    end

    first = first.to_i if first
    last = last.to_i if last

    # TODO: After querying for alerts from Elasticsearch is GA'd, there is no reason
    # to map the `per_page` parameter to `first` or `last` anymore. We can just
    # pass `per_page` directly to the ES query logic.
    # Elasticsearch rollout is tracked in https://github.com/github/dependabot-updates/issues/10504
    {
      before: before,
      after: after,
      first: first,
      last: last,
    }
  end

  def set_cursor_based_pagination_headers(page_info:, has_next_page:, has_previous_page:)
    if has_next_page
      @links.add_current({ after: page_info.end_cursor, before: nil, page: nil }, rel: "next")
    end

    if has_previous_page
      @links.add_current({ before: page_info.start_cursor, after: nil, page: nil }, rel: "prev")
    end
  end

  def alerts_for_repository(repository:)
    if GitHub.dependabot_es_search_enabled?
      alerts_from_elasticsearch(scope: repository)
    else
      alerts(repository: repository)
    end
  end

  def alerts_for_organization(organization:)
    organization.trigger_security_center_reconciliation

    if GitHub.dependabot_es_search_enabled?
      alerts_from_elasticsearch(scope: organization)
    else
      # NOTE: The below authorization checks have been moved into Search::Filters::DependabotAlertsAclFilter
      # and will be safe to remove when this codepath is fully migrated to Elasticsearch

      # If this is a request where the actor has programmatic granular
      # permissions (i.e: PAT v2, or GitHub Apps), filter the repositories before we send the request.
      programmatic_actor_grant = ProgrammaticActor::Grant.with(current_user).with_target(organization)

      # If the request is made with a programmatic actor (i.e: PAT v2, or GitHub Apps) and the actor cannot access all
      # repos in the org, we find only the repos that the actor can access.
      # When the request is made with an OAuth app or a legacy PAT, and `security_events` is not part of the scope, we find only public repos of the org.
      # Otherwise, we set `repository_ids` to `nil`, which means that the actor can access all repos in the org.
      repository_ids = if programmatic_actor_grant
        unless programmatic_actor_grant.installed_on_all_repositories?
          programmatic_actor_grant.repository_ids(min_action: :read, resource: "vulnerability_alerts")
        end
      elsif !scope?(current_user, "security_events")
        organization.repositories.public_scope.pluck(:id)
      end

      # Bail out early if the programmatic actors don't have access to
      # any of the repositories in question. This check is mostly for
      # extra safety. It seems to be hard to run into this case normally.
      if programmatic_actor_grant && repository_ids.is_a?(Array) && repository_ids.empty?
        deliver_error! 404
      end
      alerts(organization: organization, allowed_repository_ids: repository_ids)
    end
  end

  def alerts_for_enterprise(business:)
    business.trigger_security_center_reconciliation

    if GitHub.dependabot_es_search_enabled?
      alerts_from_elasticsearch(scope: business)
    else
      # NOTE: The below authorization checks have been moved into Search::Filters::DependabotAlertsAclFilter
      # and will be safe to remove when this codepath is fully migrated to Elasticsearch

      fgp = :view_dependabot_alerts
      authorized_org_ids = T.must(
        ::SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
          actor: current_user,
          business:,
          actions: fgp,
          cap_filter:,
        ).authorized_orgs_by_action[fgp]
      ).map(&:id)
      alerts(business: business, organization_ids: authorized_org_ids)
    end
  end

  private

  def alerts(repository: nil, organization: nil, allowed_repository_ids: nil, business: nil, organization_ids: nil)
    # The `query_components` must be a string of "key:value1,value2,..." pairs separated by a space.
    # For example: "ecosystem:bundler severity:critical,high"
    # These `query_components` are later parsed by the `DependabotAlertsQuery` parser, which delegates to the
    # `UngroupedAlertsQuery` for the query implementations
    query_components = params.
      slice(*Search::Queries::SecurityCenter::DependabotAlertsQuery::API_QUALIFIERS).
      map do |key, value|
        # Values can be a comma-separated String (use to signal OR) or an Array (used to signal AND).
        # We currently normalize the inputs into a list of strings
        # For most queries this means the values are ORed. The exception is the `has:` filter which ANDs the values.
        # OR support for the `has:` filter will need to be added separately in the Base parser. This is being tracked in
        # https://github.com/github/dependabot-updates/issues/9347
        values = Array(value).flat_map { |v| v.is_a?(String) ? v.split(",") : v }
        encoded_values = values.map { |val| Search::Queries::SecurityCenter::Base.encode_value(val.to_s) }.join(",")
        "#{key}:#{encoded_values}"
      end
    query_string = query_components.join(" ")

    query_hash = Search::Queries::SecurityCenter::DependabotAlertsQuery.parse_and_normalize(query_string)

    sort, direction = sort_and_direction
    sort = :"#{sort}_#{direction}"

    if repository
      query = RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(repository: repository)
    elsif organization
      query = RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(organization: organization, allowed_repository_ids: allowed_repository_ids, user: current_user)
    else
      query = RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(business: business, organization_ids: organization_ids, user: current_user)
    end

    query = query.severities_are(query_hash[:severity]).
      packages_are(query_hash[:package]).
      ecosystems_are(query_hash[:ecosystem]).
      dependency_scopes_are(query_hash[:scope]).
      epss_percentages_are(query_hash[:epss_percentage]).
      artifact_registry_urls_are(query_hash[:artifact_registry_url]).
      artifact_registries_are(query_hash[:artifact_registry]).
      runtime_risks_are(query_hash[:runtime_risk]).
      has_a(query_hash[:has]).
      sort_by(sort)

    if repository.present? && query_hash[:manifest].present?
      query = query.manifests_are(query_hash[:manifest])
    end

    if !allow_malware_queries?(repository || organization || business)
      params.delete(Search::Queries::SecurityCenter::DependabotAlertsQuery::QUALIFIER_CLASSIFICATION)
    end

    if type = params[Search::Queries::SecurityCenter::DependabotAlertsQuery::QUALIFIER_CLASSIFICATION]
      query = query.vulnerability_types_are([type])
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

    alerts, alerts_platform_relation = GitHub.dogstats.distribution_time(
      "dependabot_alerts.index.query_time",
      tags: query.datadog_tags + ["source:api", "read_from:db"]
    ) do
      get_cursor_paginated_alerts(alerts)
    end

    set_cursor_based_pagination_headers(
      page_info: alerts_platform_relation.page_info,
      has_next_page: alerts_platform_relation.has_next_page,
      has_previous_page: alerts_platform_relation.has_previous_page,
    ) if alerts.any?

    filtered_alerts, _ = filter_tenant_rows(
      query.tenant_filter_scope,
      alerts,
      -> (alert) { alert.repository_id }
    )

    filtered_alerts
  end

  def allow_malware_queries?(scope)
    actors = [current_user, scope]
    actors.push(scope, scope.owner) if scope.is_a?(Repository)

    FeatureFlag.vexi.enabled?(:dependabot_allow_malware_frontend, *actors, default: false)
  end

  def alerts_from_elasticsearch(scope:)
    # This API does not support offset pagination
    if params.key?(:page)
      deliver_error!(400, message: "Pagination using the `page` parameter is not supported.")
    end

    if !allow_malware_queries?(scope)
      params.delete(Search::Queries::SecurityCenter::DependabotAlertsQuery::QUALIFIER_CLASSIFICATION)
    end

    es_qualifiers = Search::Queries::SecurityCenter::DependabotAlertsQuery::ES_API_QUALIFIERS

    query_params = params.slice(*es_qualifiers).
      flat_map do |key, value|
        # Values can be a comma-separated String (used to signal OR) or an Array (used to signal AND).
        # We currently normalize the inputs into a list of strings
        case value
        when String then "#{key}:#{value}"
        when Array then value.map { |v| "#{key}:#{v}" }
        end
      end

    sort, direction = sort_and_direction
    query_params << "sort:#{sort}-#{direction}"

    # Validate the pagination params using the existing platform GraphQL logic,
    # without actually paginating any data.
    pagination_params = cursor_pagination_params.compact
    Platform::ConnectionWrappers::Relation.new(nil, **pagination_params).validate_arguments!

    query_string = query_params.compact.join(" ")

    result = GitHub.dogstats.distribution_time(
      "dependabot_alerts.index.query_time",
      tags: ["source:api", "read_from:es", "context:#{scope.class.name.underscore}"]
    ) do
      query = Search::Queries::DependabotAlertsEsQuery.new(
        phrase: query_string,
        current_user:,
        scope:,
        cap_filter:,
        **pagination_params,
      )

      log_search_after_vs_sort_inconsistencies(scope, query.query_document)

      query.execute
    end

    # Search::Responses::CursorPaginationResponse provides all data
    # needed to set cursor-based pagination headers
    set_cursor_based_pagination_headers(
      page_info: result,
      has_next_page: result.has_next_page?,
      has_previous_page: result.has_previous_page?,
    ) if result.total > 0

    filtered_alerts, _ = filter_tenant_rows(
      GitHub::SecurityCenter::TenantFilteringHelper::RequestScope.new(
        scope.class.name.underscore.to_sym,
        scope,
        SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS
      ),
      result.models,
      -> (alert) { alert.repository_id }
    )

    filtered_alerts
  rescue Search::Filters::DependabotAlertsAclFilter::Error
    deliver_error!(404)
  end

  def sort_and_direction
    direction = params[:direction] == "asc" ? "asc" : "desc"
    sort = case params[:sort]
    when "epss_percentage", "epss-percentage"
      :epss_percentage
    when "updated"
      :last_state_change_at
    else
      :created
    end

    [sort, direction]
  end

  def alerts_requested_by_site_admin?
    current_user&.site_admin? && env["REQUEST_METHOD"] == "GET"
  end

  # TODO: this is temporary logging to help verify whether a cursor/sort
  # API query mismatch is related to the MySQL -> ES transition.
  # https://github.sentry.io/issues/4207281208/events/1725edcf499c46ac90bb87328818764c/
  def log_search_after_vs_sort_inconsistencies(scope, query_document)
    return unless query_document[:search_after] && query_document[:sort]
    return if query_document[:search_after].size == query_document[:sort].size

    # The running theory is that the cursor value (search_after) contains an array with a single value - an alert id.
    # Whereas the ES sorts always contain at least two values - a score value and an alert id - but will probably also
    # also contain additional sort values like created_at.
    # We can validate this by logging the cursor and sort values along with the query scope.
    # When we get log hits we can check whether the cursor value is the id for an alert in the repo/owner/business scope
    # denoted by query_scope.  It's not a perfect method but should give us confidence to suggest to users that they
    # need to refresh whatever automation they're running with new paginated search links.
    GitHub.logger.info(
      msg: "Dependabot alerts ES query has inconsistent search_after and sort sizes",
      search_after: query_document[:search_after],
      sort: query_document[:sort],
      query_scope: "#{scope.class.name}:#{scope.id}",
    )
  end
end
