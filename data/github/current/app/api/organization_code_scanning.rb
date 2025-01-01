# typed: true
# frozen_string_literal: true

class Api::OrganizationCodeScanning < Api::App
  include Api::App::CodeScanningHelpers
  include GitHub::SecurityCenter::TenantFilteringHelper

  # get a list of code scanning alerts for a private repository.
  get "/organizations/:organization_id/code-scanning/alerts", operation_id: "code-scanning/list-alerts-for-org" do
    # Ensure the org is capable of having code scanning alerts
    deliver_error!(404) unless org.alerts_code_scanning_external_api_enabled?

    control_access :list_org_code_scanning_alerts,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if access_allowed?(:list_org_code_scanning_alerts_for_only_public_repos, resource: org, allow_integrations: false, allow_user_via_granular_actor: false)
      GitHub.dogstats.increment("code_scanning.api.org_alerts.public_repo_PAT_scope")
    end

    state = GitHub::Turboscan.to_alert_state_filter(params[:state])
    sort_order = GitHub::Turboscan.api_to_alert_sort_order(params[:sort], params[:direction])

    # If this is a request where the actor has programmatic granular
    # permissions, filter the repositories before we send the request.
    programmatic_actor_grant = ProgrammaticActor::Grant.with(current_user).with_target(org)

    repository_ids = if programmatic_actor_grant && !programmatic_actor_grant.installed_on_all_repositories?
      programmatic_actor_grant.repository_ids(min_action: :read, resource: "security_events")
    end

    # Bail out early if the programmatic actors don't have access to
    # any of the repositories in question.
    if repository_ids.is_a?(Array) && repository_ids.empty?
      deliver_error! 404
    end

    ensure_non_conflicting_cursor_params!
    ensure_non_conflicting_tool_params!

    severity = GitHub::Turboscan.to_severity(params[:severity]) if params[:severity]

    req_params = {
      owner_ids: [org.id],
      repository_ids: repository_ids,
      state: state,
      limit: per_page,
      numeric_page: pagination[:page],
      before_cursor: params[:before],
      after_cursor: params[:after],
      sort_order: sort_order,
      tools: [params[:tool_name]].compact,
      tool_guids: [params[:tool_guid]].compact,
      repository_visibilities: from_repo_visibilities_to_proto_enums(repo_visibilities),
      severities: [severity].compact,
    }

    response = GitHub::Turboscan.alerts_by_repo(req_params)

    if response&.error&.code == :not_found
      deliver_error! 404
    elsif response.blank? || response.error.present?
      deliver_code_scanning_unavailable_error!
    end

    repo_results = response.data.results

    # filter results to avoid leaking repos outside of the org due to turboscan inconsistencies
    repo_results, repos_by_id = filter_tenant_rows(
      RequestScope.new(:organization, org, "code_scanning"),
      repo_results,
      -> (result) { result.repository_id },
      repo_visibilities
    )

    # filter results to only those repos that the actor has access to, in case turboscan returned extra results
    repo_results.select! { |r| repository_ids.include?(r.repository_id) } unless repository_ids.nil?

    # Add prev/next links
    prev_cursor = response.data.prev_cursor
    next_cursor = response.data.next_cursor
    if prev_cursor.present?
      @links.add_current({ after: nil, before: prev_cursor, page: nil }, rel: "prev")
    end
    if next_cursor.present?
      @links.add_current({ after: next_cursor, before: nil, page: nil }, rel: "next")
    end

    deliver :org_code_scanning_alerts_hash, { repo_results: repo_results, repos_by_id: repos_by_id }
  end

  private

  def org
    return @_org if defined?(@_org)
    @_org = find_org!
  end

  def repo_visibilities
    @_repo_visibilities ||= begin
      if access_allowed?(:list_org_code_scanning_alerts_for_only_public_repos, resource: org, allow_integrations: false, allow_user_via_granular_actor: false)
        [Repository::PUBLIC_VISIBILITY]
      else
        Repository::VISIBILITIES
      end
    end
  end
end
