# typed: true
# frozen_string_literal: true

class Api::EnterpriseCodeScanning < Api::Enterprise::App
  include Api::App::CodeScanningHelpers

  get "/enterprises/:enterprise_id/code-scanning/alerts", operation_id: "code-scanning/list-alerts-for-enterprise" do
    deliver_error! 404 unless GitHub.code_scanning_enabled?

    business = find_enterprise!
    deliver_error! 404 unless business&.advanced_security_purchased?

    control_access :list_enterprise_code_scanning_alerts,
      resource: business,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    ensure_non_conflicting_cursor_params!
    ensure_non_conflicting_tool_params!

    fgp = :read_code_scanning
    authorized_org_ids = T.must(
      ::SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
        actor: current_user,
        business:,
        actions: fgp,
        cap_filter:,
      ).authorized_orgs_by_action[fgp]
    ).map(&:id)

    deliver! :enterprise_code_scanning_alerts_hash, { repo_results: [] } if authorized_org_ids.empty?

    response = GitHub::Turboscan.alerts_by_repo(
      owner_ids: authorized_org_ids,
      limit: per_page,
      numeric_page: pagination[:page],
      before_cursor: params[:before],
      after_cursor: params[:after],
      state: GitHub::Turboscan.to_alert_state_filter(params[:state]),
      sort_order: GitHub::Turboscan.api_to_alert_sort_order(params[:sort], params[:direction]),
      tools: [params[:tool_name]].compact,
      tool_guids: [params[:tool_guid]].compact
    )

    if response&.error&.code == :not_found
      deliver_error! 404
    elsif response.blank? || response.error.present?
      deliver_code_scanning_unavailable_error!
    end

    # Add prev/next links
    if (prev_cursor = response.data&.prev_cursor).present?
      @links.add_current({ after: nil, before: prev_cursor, page: nil }, rel: "prev")
    end
    if (next_cursor = response.data&.next_cursor).present?
      @links.add_current({ after: next_cursor, before: nil, page: nil }, rel: "next")
    end

    repo_results = response.data&.results || []
    repos_by_id = Repository.where(owner_id: authorized_org_ids, id: repo_results.map(&:repository_id))
      .preload(:owner) # For the 'repo.owner' calls when building the 'repository' entry in the result hash
      .index_by(&:id)

    # Filter results to avoid leaking repos outside of the authorized orgs due to Turboscan inconsistencies
    repo_results.select! { |r| repos_by_id.key?(r.repository_id) }

    deliver :enterprise_code_scanning_alerts_hash, { repo_results: repo_results, repos_by_id: repos_by_id }
  end
end
