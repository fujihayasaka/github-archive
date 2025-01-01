# typed: true
# frozen_string_literal: true

class Api::ActionsCache < Api::App
  include FeatureFlagHelper
  include Api::App::TwirpHelpers
  include ActionsCacheHelper

  ADMIN_RIGHTS_ERROR_MESSAGE = T.let("You must have admin rights to the Repository.".freeze, String)

  # List caches for a repository
  get "/repositories/:repository_id/actions/caches", operation_id: "actions/get-actions-cache-list" do
    repo = find_repo!
    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    # validate parameters
    receive_with_openapi

    # fetch data from launch
    actions_caches_data = handle_twirp_errors do
      ActionsCacheManagementHelper.get_repo_caches(repo:, key: params["key"], ref: params["ref"], per_page:, page:, sort:, direction:)
    end

    # adding pagination headers
    last_page = (actions_caches_data.total_caches / per_page.to_f).ceil
    if actions_caches_data.total_caches > per_page
      @links.add_current({ page: last_page }, rel: "last") if current_page != last_page
      @links.add_current({ page: current_page + 1 }, rel: "next") if current_page < last_page
    end
    if current_page && current_page > 1
      @links.add_current({ page: 1 }, rel: "first")
      prev_page = (current_page <= last_page) ? current_page - 1 : 1
      @links.add_current({ page: prev_page }, rel: "prev")
    end

    # form response object
    deliver :caches_hash, { actions_caches: { total_count: actions_caches_data.total_caches, actions_caches: actions_caches_data.caches } }
  end

  # delete caches by key for a repository
  delete "/repositories/:repository_id/actions/caches", operation_id: "actions/delete-actions-cache-by-key" do
    repo = find_repo!
    control_access :write_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    # validate parameters
    receive_with_openapi

    # fetch data from launch
    actions_caches_data = handle_twirp_errors do
      ActionsCacheManagementHelper.deletes_repo_cache_by_key(repo:, key: params["key"], ref: params["ref"], current_user:)
    end

    # form response object
    deliver :caches_hash, { actions_caches: { total_count: actions_caches_data.total_caches, actions_caches: actions_caches_data.caches } }
  end

  # Delete cache for a repository by its id
  delete "/repositories/:repository_id/actions/caches/:cache_id", operation_id: "actions/delete-actions-cache-by-id" do
    repo = find_repo!
    control_access :write_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    handle_twirp_errors do
      ActionsCacheManagementHelper.delete_repo_cache_by_id(repo:, id: params[:cache_id].to_i, current_user:)
    end

    deliver_empty status: 204
  end

  # List cache usage for a repository
  get "/repositories/:repository_id/actions/cache/usage", operation_id: "actions/get-actions-cache-usage" do
    repo = find_repo!
    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    cache_usage = ActionsCacheUsage.get_repo_cache_usage(repo)
    deliver :cache_usage_hash, { cache_usage: cache_usage, repository: repo }
  end

  # Get the cache usage policy for a repository
  get "/repositories/:repository_id/actions/cache/usage-policy", operation_id: "actions/get-actions-cache-usage-policy" do
    deliver_error! 404 unless GitHub.enterprise?

    repo = find_repo!
    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    limit = ActionsCacheUsagePolicy.get_repository_cache_usage_policy(current_repository: repo)
    deliver :cache_usage_policy_hash, { repo_cache_size_limit_in_gb: limit }
  end

  # Modify cache usage policy for a repository
  patch "/repositories/:repository_id/actions/cache/usage-policy", operation_id: "actions/set-actions-cache-usage-policy" do
    deliver_error! 404 unless GitHub.enterprise?

    repo = find_repo!
    control_access :write_admin_actions_repo,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi

    ActionsCacheUsagePolicy.update_repository_cache_usage_policy(current_repository: repo, limit: data["repo_cache_size_limit_in_gb"], actor: current_user)
    deliver_empty status: 204

  rescue ActionsCacheUsagePolicy::InvalidLimitError => e
    deliver_error! 400, message: e.message
  end

  # Get cache storage limit for repository.
  get "/repositories/:repository_id/actions/cache/storage-limit", operation_id: "actions/get-actions-cache-storage-limit-for-repository", read_from_replicas: true do
    deliver_error! 404 if GitHub.enterprise?
    repo = find_repo!
    deliver_error! 404 unless FeatureFlag.vexi.enabled?("actions_cache_use_storage_and_retention_policies", Billing::EntityResolver.billing_owner(repo), default: false)

    deliver_error! 402, message: ActionsPolicyHelper::ACTIONS_CACHE_NONBILLABLE_MESSAGE unless ActionsPolicyHelper.entity_can_use_cache_policies?(repo)

    control_access :read_admin_actions,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: repo.public?,
      forbid_message: ADMIN_RIGHTS_ERROR_MESSAGE,
      enforce_oauth_app_policy: true

    deliver :cache_storage_limit_hash, {
      max_cache_size_gb: ActionsPolicyHelper.get_applied_cache_storage_limit(repo)
    }
  end

  # Set cache storage limit for repository.
  put "/repositories/:repository_id/actions/cache/storage-limit", operation_id: "actions/set-actions-cache-storage-limit-for-repository", read_from_replicas: true do
    deliver_error! 404 if GitHub.enterprise?
    repo = current_repo
    deliver_error! 404 unless FeatureFlag.vexi.enabled?("actions_cache_use_storage_and_retention_policies", Billing::EntityResolver.billing_owner(repo), default: false)

    deliver_error! 402, message: ActionsPolicyHelper::ACTIONS_CACHE_NONBILLABLE_MESSAGE unless ActionsPolicyHelper.entity_can_use_cache_policies?(repo)

    control_access :write_admin_actions_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: repo.public?,
      forbid_message: ADMIN_RIGHTS_ERROR_MESSAGE

    data = receive_with_openapi

    ActionsPolicyHelper.upsert_cache_storage_policy(repo, data["max_cache_size_gb"], current_user: current_user)
    deliver_empty status: 204

  rescue ActionsCacheUsagePolicy::InvalidLimitError => e
    deliver_error! 400, message: e.message
  end


  # Get cache retention limit for repository.
  get "/repositories/:repository_id/actions/cache/retention-limit", operation_id: "actions/get-actions-cache-retention-limit-for-repository", read_from_replicas: true do
    deliver_error! 404 if GitHub.enterprise?
    repo = find_repo!
    deliver_error! 404 unless FeatureFlag.vexi.enabled?("actions_cache_use_storage_and_retention_policies", Billing::EntityResolver.billing_owner(repo), default: false)

    deliver_error! 402, message: ActionsPolicyHelper::ACTIONS_CACHE_NONBILLABLE_MESSAGE unless ActionsPolicyHelper.entity_can_use_cache_policies?(repo)

    control_access :read_admin_actions,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: repo.public?,
      forbid_message: ADMIN_RIGHTS_ERROR_MESSAGE

    deliver :cache_retention_limit_hash, {
      retain_for: ActionsPolicyHelper.get_applied_cache_retention(repo)
    }
  end

  # Set cache retention limit for repository.
  put "/repositories/:repository_id/actions/cache/retention-limit", operation_id: "actions/set-actions-cache-retention-limit-for-repository", read_from_replicas: true do
    deliver_error! 404 if GitHub.enterprise?
    repo = find_repo!
    deliver_error! 404 unless FeatureFlag.vexi.enabled?("actions_cache_use_storage_and_retention_policies", Billing::EntityResolver.billing_owner(repo), default: false)

    deliver_error! 402, message: ActionsPolicyHelper::ACTIONS_CACHE_NONBILLABLE_MESSAGE unless ActionsPolicyHelper.entity_can_use_cache_policies?(repo)

    control_access :write_admin_actions_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: repo.public?,
      forbid_message: ADMIN_RIGHTS_ERROR_MESSAGE

    data = receive_with_openapi

    ActionsPolicyHelper.upsert_cache_retention_policy(repo, data["max_cache_retention_days"], current_user: current_user)
    deliver_empty status: 204

  rescue ActionsCacheUsagePolicy::InvalidLimitError => e
    deliver_error! 400, message: e.message
  end

  private

  def per_page
    pagination[:per_page] || 30
  end

  def page
    pagination[:page] || 1
  end

  def direction
    params[:direction] || "desc"
  end

  def sort
    params[:sort] || "last_accessed_at"
  end
end
