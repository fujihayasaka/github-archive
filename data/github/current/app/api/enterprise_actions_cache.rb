# typed: true
# frozen_string_literal: true

class Api::EnterpriseActionsCache < Api::Enterprise::App
  include FeatureFlagHelper

  ADMIN_RIGHTS_ERROR_MESSAGE = T.let("Must have admin rights to Enterprise.", String)

  # Get cache usage for enterprise.
  get "/enterprises/:enterprise_id/actions/cache/usage", operation_id: "actions/get-actions-cache-usage-for-enterprise" do
    current_enterprise = find_enterprise!
    deliver_error! 404 unless GitHub.actions_enabled?

    control_access :read_actions_cache_admin_enterprise,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: ADMIN_RIGHTS_ERROR_MESSAGE

    scope = ActionsCacheUsage.get_enterprise_cache_usage(current_enterprise)
    deliver :enterprise_cache_usage_hash, scope
  end

  # Get cache usage limit for enterprise.
  get "/enterprises/:enterprise_id/actions/cache/usage-policy", operation_id: "actions/get-actions-cache-usage-policy-for-enterprise" do
    deliver_error! 404 unless GitHub.enterprise?
    current_enterprise = find_enterprise!

    control_access :read_actions_cache_admin_enterprise,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: ADMIN_RIGHTS_ERROR_MESSAGE

    scope = ActionsCacheUsagePolicy.get_enterprise_cache_usage_policy(current_enterprise: current_enterprise)
    deliver :enterprise_cache_usage_policy_hash, scope
  end

  # Set cache usage limit for enterprise.
  patch "/enterprises/:enterprise_id/actions/cache/usage-policy", operation_id: "actions/set-actions-cache-usage-policy-for-enterprise" do
    deliver_error! 404 unless GitHub.enterprise?
    current_enterprise = find_enterprise!

    control_access :write_actions_cache_admin_enterprise,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: ADMIN_RIGHTS_ERROR_MESSAGE

    data = receive_with_openapi

    ActionsCacheUsagePolicy.update_enterprise_cache_usage_policy(current_enterprise: current_enterprise, limit: data["repo_cache_size_limit_in_gb"], upper_limit: data["max_repo_cache_size_limit_in_gb"], actor: current_user)
    deliver_empty status: 204

  rescue ActionsCacheUsagePolicy::InvalidLimitError => e
    deliver_error! 400, message: e.message
  end

  # Get cache storage limit for enterprise.
  get "/enterprises/:enterprise_id/actions/cache/storage-limit", operation_id: "actions/get-actions-cache-storage-limit-for-enterprise", read_from_replicas: true do
    deliver_error! 404 if GitHub.enterprise?
    current_enterprise = find_enterprise!
    deliver_error! 404 unless FeatureFlag.vexi.enabled?("actions_cache_use_storage_and_retention_policies", current_enterprise, default: false)
    deliver_error! 402, message: ActionsPolicyHelper::ACTIONS_CACHE_NONBILLABLE_MESSAGE unless ActionsPolicyHelper.entity_can_use_cache_policies?(current_enterprise)

    control_access :read_actions_cache_admin_enterprise,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: ADMIN_RIGHTS_ERROR_MESSAGE

    deliver :cache_storage_limit_hash, {
      max_cache_size_gb: ActionsPolicyHelper.get_applied_cache_storage_limit(current_enterprise)
    }
  end

  # Set cache storage limit for enterprise.
  put "/enterprises/:enterprise_id/actions/cache/storage-limit", operation_id: "actions/set-actions-cache-storage-limit-for-enterprise", read_from_replicas: true do
    deliver_error! 404 if GitHub.enterprise?
    current_enterprise = find_enterprise!
    deliver_error! 404 unless FeatureFlag.vexi.enabled?("actions_cache_use_storage_and_retention_policies", current_enterprise, default: false)
    deliver_error! 402, message: ActionsPolicyHelper::ACTIONS_CACHE_NONBILLABLE_MESSAGE unless ActionsPolicyHelper.entity_can_use_cache_policies?(current_enterprise)

    control_access :write_actions_cache_admin_enterprise,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: ADMIN_RIGHTS_ERROR_MESSAGE

    data = receive_with_openapi

    ActionsPolicyHelper.upsert_cache_storage_policy(current_enterprise, data["max_cache_size_gb"], current_user: current_user)
    deliver_empty status: 204

  rescue ActionsCacheUsagePolicy::InvalidLimitError => e
    deliver_error! 400, message: e.message
  end


  # Get cache retention limit for enterprise.
  get "/enterprises/:enterprise_id/actions/cache/retention-limit", operation_id: "actions/get-actions-cache-retention-limit-for-enterprise", read_from_replicas: true do
    deliver_error! 404 if GitHub.enterprise?
    current_enterprise = find_enterprise!
    deliver_error! 404 unless FeatureFlag.vexi.enabled?("actions_cache_use_storage_and_retention_policies", current_enterprise, default: false)
    deliver_error! 402, message: ActionsPolicyHelper::ACTIONS_CACHE_NONBILLABLE_MESSAGE unless ActionsPolicyHelper.entity_can_use_cache_policies?(current_enterprise)

    control_access :read_actions_cache_admin_enterprise,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: ADMIN_RIGHTS_ERROR_MESSAGE

    deliver :cache_retention_limit_hash, {
      retain_for: ActionsPolicyHelper.get_applied_cache_retention(current_enterprise)
    }
  end

  # Set cache retention limit for enterprise.
  put "/enterprises/:enterprise_id/actions/cache/retention-limit", operation_id: "actions/set-actions-cache-retention-limit-for-enterprise", read_from_replicas: true do
    deliver_error! 404 if GitHub.enterprise?
    current_enterprise = find_enterprise!
    deliver_error! 404 unless FeatureFlag.vexi.enabled?("actions_cache_use_storage_and_retention_policies", current_enterprise, default: false)
    deliver_error! 402, message: ActionsPolicyHelper::ACTIONS_CACHE_NONBILLABLE_MESSAGE unless ActionsPolicyHelper.entity_can_use_cache_policies?(current_enterprise)

    control_access :write_actions_cache_admin_enterprise,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: ADMIN_RIGHTS_ERROR_MESSAGE

    data = receive_with_openapi

    ActionsPolicyHelper.upsert_cache_retention_policy(current_enterprise, data["max_cache_retention_days"], current_user: current_user)
    deliver_empty status: 204

  rescue ActionsCacheUsagePolicy::InvalidLimitError => e
    deliver_error! 400, message: e.message
  end
end
