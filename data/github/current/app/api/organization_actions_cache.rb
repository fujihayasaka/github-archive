# typed: true
# frozen_string_literal: true

class Api::OrganizationActionsCache < Api::App
  include FeatureFlagHelper

  # List cache usage by repository in an organization.
  get "/organizations/:organization_id/actions/cache/usage-by-repository", operation_id: "actions/get-actions-cache-usage-by-repo-for-org" do
    org = find_org!
    control_access :read_org_actions_cache,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_CACHE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    cache_usage = ActionsCacheUsage.get_org_cache_usage_order_by_size_with_repo_details(org.id, pagination[:page], pagination[:per_page])
    deliver :org_cache_usage_by_repo_hash, { cache_usage: cache_usage, total_count: cache_usage.total_entries }
  end

  # Get cache usage in an organization.
  get "/organizations/:organization_id/actions/cache/usage", operation_id: "actions/get-actions-cache-usage-for-org" do
    org = find_org!
    control_access :read_org_actions_cache,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_CACHE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    scope = ActionsCacheUsage.get_org_cache_usage(org.id)
    deliver :org_cache_usage_hash, scope
  end
end
