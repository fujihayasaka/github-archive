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

  # Get cache storage limit for enterprise.
  get "/organizations/:organization_id/actions/cache/storage-limit", operation_id: "actions/get-actions-cache-storage-limit-for-organization", read_from_replicas: true do
    deliver_error! 404 if GitHub.enterprise?
    org = find_org!
    deliver_error! 404 unless FeatureFlag.vexi.enabled?("actions_cache_use_storage_and_retention_policies", Billing::EntityResolver.billing_owner(org), default: false)
    deliver_error! 402, message: ActionsPolicyHelper::ACTIONS_CACHE_NONBILLABLE_MESSAGE unless ActionsPolicyHelper.entity_can_use_cache_policies?(org)

    control_access :read_actions_settings_org,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_CACHE_FORBIDDEN_MESSAGE

    deliver :cache_storage_limit_hash, {
      max_cache_size_gb: ActionsPolicyHelper.get_applied_cache_storage_limit(org)
    }
  end

  # Set cache storage limit for enterprise.
  put "/organizations/:organization_id/actions/cache/storage-limit", operation_id: "actions/set-actions-cache-storage-limit-for-organization", read_from_replicas: true do
    deliver_error! 404 if GitHub.enterprise?
    org = find_org!
    deliver_error! 404 unless FeatureFlag.vexi.enabled?("actions_cache_use_storage_and_retention_policies", Billing::EntityResolver.billing_owner(org), default: false)
    deliver_error! 402, message: ActionsPolicyHelper::ACTIONS_CACHE_NONBILLABLE_MESSAGE unless ActionsPolicyHelper.entity_can_use_cache_policies?(org)

    control_access :write_actions_settings_org,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_CACHE_FORBIDDEN_MESSAGE

    data = receive_with_openapi

    ActionsPolicyHelper.upsert_cache_storage_policy(org, data["max_cache_size_gb"], current_user: current_user)
    deliver_empty status: 204

  rescue ActionsCacheUsagePolicy::InvalidLimitError => e
    deliver_error! 400, message: e.message
  end


  # Get cache retention limit for enterprise.
  get "/organizations/:organization_id/actions/cache/retention-limit", operation_id: "actions/get-actions-cache-retention-limit-for-organization", read_from_replicas: true do
    deliver_error! 404 if GitHub.enterprise?
    org = find_org!
    deliver_error! 404 unless FeatureFlag.vexi.enabled?("actions_cache_use_storage_and_retention_policies", Billing::EntityResolver.billing_owner(org), default: false)
    deliver_error! 402, message: ActionsPolicyHelper::ACTIONS_CACHE_NONBILLABLE_MESSAGE unless ActionsPolicyHelper.entity_can_use_cache_policies?(org)

    control_access :read_actions_settings_org,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_CACHE_FORBIDDEN_MESSAGE

    deliver :cache_retention_limit_hash, {
      retain_for: ActionsPolicyHelper.get_applied_cache_retention(org)
    }
  end

  # Set cache retention limit for enterprise.
  put "/organizations/:organization_id/actions/cache/retention-limit", operation_id: "actions/set-actions-cache-retention-limit-for-organization", read_from_replicas: true do
    deliver_error! 404 if GitHub.enterprise?
    org = find_org!
    deliver_error! 404 unless FeatureFlag.vexi.enabled?("actions_cache_use_storage_and_retention_policies", Billing::EntityResolver.billing_owner(org), default: false)
    deliver_error! 402, message: ActionsPolicyHelper::ACTIONS_CACHE_NONBILLABLE_MESSAGE unless ActionsPolicyHelper.entity_can_use_cache_policies?(org)

    control_access :write_actions_settings_org,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_CACHE_FORBIDDEN_MESSAGE

    data = receive_with_openapi

    ActionsPolicyHelper.upsert_cache_retention_policy(org, data["max_cache_retention_days"], current_user: current_user)
    deliver_empty status: 204

  rescue ActionsCacheUsagePolicy::InvalidLimitError => e
    deliver_error! 400, message: e.message
  end
end
