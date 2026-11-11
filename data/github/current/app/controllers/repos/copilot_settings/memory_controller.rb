# typed: true
# frozen_string_literal: true

class Repos::CopilotSettings::MemoryController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Copilot::MemoryBillingEntityDecoration

  allow_verified_fetch only: [:destroy, :update_memory_disabled]

  before_action :login_required
  before_action :ensure_admin_access
  before_action :dotcom_required
  before_action :copilot_memory_enabled?
  before_action :parse_json_params, only: [:update_memory_disabled]

  depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Copilot,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Iam

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Repos::CopilotSettings::MemoryController#update_memory_disabled",
  ].freeze

  class IndexPayload < ReactPayload::Base
    def route_id
      "indexRoute"
    end

    def payload
      {
          memories: @memories,
          loadError: @load_error,
          # Memory opt-out settings
          memoryOptOutEnabled: @memory_opt_out_enabled,
          memoryDisabled: @memory_disabled,
          updateMemoryDisabledPath: @update_memory_disabled_path,
      }
    end

    def initialize(memories:, load_error: false, memory_opt_out_enabled: false, memory_disabled: false, update_memory_disabled_path: nil)
      @memories = memories
      @load_error = load_error
      @memory_opt_out_enabled = memory_opt_out_enabled
      @memory_disabled = memory_disabled
      @update_memory_disabled_path = update_memory_disabled_path
    end
  end

  def self.react_bundle_name
    "copilot-memory"
  end

  # GET /:owner/:repo/settings/copilot/memory
  # Fetches and renders the list of Copilot memories for the current repository.
  def index
    load_error = false
    begin
      # We will fetch a large, but bounded number of memories to display in the UI.
      # Note: :results can be nil when the API returns a blank body, so we default to [].
      memories = copilot_api.get_top_memories(owner: current_repository.owner_display_login, repo: current_repository.name, limit: 500, request_timeout_s: 2.0, staging_env: staging_env).fetch(:results, []) || []
      GitHub.logger.info("Copilot memory fetch succeeded", {
        "gh.repo.id" => current_repository.id,
        "gh.repo.name" => current_repository.full_name,
        "gh.copilot_memory.count" => memories.size,
      })
      GitHub.dogstats.increment("copilot_memory.fetch", tags: ["result:success"])
    rescue CopilotAPI::NetworkError => e
      GitHub.logger.error("Copilot memory fetch failed: network/timeout error", {
        "gh.repo.id" => current_repository.id,
        "gh.repo.name" => current_repository.full_name,
        "gh.error.message" => e.message,
        "gh.error.class" => e.class.name,
      })
      GitHub.dogstats.increment("copilot_memory.fetch", tags: ["result:error", "error_type:network"])
      memories = []
      load_error = true
    rescue CopilotAPI::UnauthorizedError => e
      GitHub.logger.error("Copilot memory fetch failed: unauthorized", {
        "gh.repo.id" => current_repository.id,
        "gh.repo.name" => current_repository.full_name,
        "gh.error.message" => e.message,
        "gh.error.class" => e.class.name,
      })
      GitHub.dogstats.increment("copilot_memory.fetch", tags: ["result:error", "error_type:unauthorized"])
      memories = []
      load_error = true
    rescue CopilotAPI::RateLimitError => e
      GitHub.logger.error("Copilot memory fetch failed: rate limited", {
        "gh.repo.id" => current_repository.id,
        "gh.repo.name" => current_repository.full_name,
        "gh.error.message" => e.message,
        "gh.error.class" => e.class.name,
      })
      GitHub.dogstats.increment("copilot_memory.fetch", tags: ["result:error", "error_type:rate_limit"])
      memories = []
      load_error = true
    rescue CopilotAPI::Error => e
      GitHub.logger.error("Copilot memory fetch failed", {
        "gh.repo.id" => current_repository.id,
        "gh.repo.name" => current_repository.full_name,
        "gh.error.message" => e.message,
        "gh.error.class" => e.class.name,
      })
      GitHub.dogstats.increment("copilot_memory.fetch", tags: ["result:error", "error_type:other"])
      memories = []
      load_error = true
    end

    payload = IndexPayload.new(
      memories: decorate_memories_with_billing_entity(memories),
      load_error: load_error,
      memory_opt_out_enabled: memory_opt_out_enabled?,
      memory_disabled: memory_disabled_for_repo?,
      update_memory_disabled_path: memory_opt_out_enabled? ? helpers.repo_repo_settings_copilot_memory_update_disabled_path(current_repository.owner_display_login, current_repository.name) : nil,
    )
    respond_with_react(
      title: "Copilot memory",
      payload: payload,
      page_data: { selected_link: :repo_settings_copilot_memory },
      layout: "layouts/repository/edit_repositories")
  end

  # DELETE /:owner/:repo/settings/copilot/memory
  # Deletes one or more Copilot memories. Dispatches to the singular API endpoint
  # for single deletions and the batch endpoint for multiple deletions.
  # Accepts params[:id] (single) or params[:ids] (array).
  def destroy
    ids_param = params[:ids] || params[:id]
    memory_ids = Array(ids_param).flatten.compact.reject(&:blank?)
    return render(json: { error: "Memory IDs are required for deletion" }, status: :bad_request) if memory_ids.empty?

    begin
      deleted_ids, not_deleted_ids = if memory_ids.size == 1
        delete_single_memory(memory_ids.first)
      else
        delete_memories_batch(memory_ids)
      end

      render_delete_result(memory_ids, deleted_ids, not_deleted_ids)
    rescue StandardError => e
      GitHub.logger.error("Copilot memory delete failed: unexpected error", {
        "gh.repo.id" => current_repository.id,
        "gh.repo.name" => current_repository.full_name,
        "gh.error.message" => e.message,
        "gh.error.class" => e.class.name,
      })
      GitHub.dogstats.increment("copilot_memory.delete", tags: ["result:error", "error_type:unexpected"])
      render json: {}, status: :internal_server_error
    end
  end

  # PUT /:owner/:repo/settings/copilot/memory/disabled
  # Toggle whether agentic memory is disabled for this repository.
  # When enabled (memory_disabled=true), sweagentd will not store or retrieve
  # repository-scoped memories for this repo. User-scoped memories are unaffected.
  def update_memory_disabled # rubocop:disable GitHub/UseRestfulActions
    return render_404 unless memory_opt_out_enabled?

    disabled = params[:memory_disabled]
    unless disabled.is_a?(TrueClass) || disabled.is_a?(FalseClass)
      return render json: { error: "The 'memory_disabled' parameter is required and must be a boolean" }, status: :unprocessable_entity
    end

    config = Copilot::SweAgentConfiguration.find_or_initialize_by(resource: current_repository)
    config.memory_disabled = disabled
    config.updated_by = current_user

    if config.save
      render json: {
        message: "Setting saved successfully",
        memoryDisabled: config.memory_disabled,
      }
    else
      render json: { message: config.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  # before_action guard that returns 404 unless the Copilot memory feature flag
  # is enabled for the current user and the memory policy is set to "enabled".
  def copilot_memory_enabled? # rubocop:disable GitHub/UseRestfulActions
    unless FeatureFlag.vexi.enabled?("copilot_memory_enablement_policy", current_user, default: false) &&
      Copilot::Policies::Memory.effective_value(current_copilot_user) == "enabled"
      render_404
    end
  end

  private

  # Whether the memory opt-out feature is enabled for this repository.
  def memory_opt_out_enabled?
    FeatureFlag.vexi.enabled?(:copilot_repo_memory_opt_out, current_repository, default: false)
  end

  # Whether memory is currently disabled for this repository via SweAgentConfiguration.
  def memory_disabled_for_repo?
    config = Copilot::SweAgentConfiguration.find_by(resource: current_repository)
    config&.memory_disabled == true
  end

  # Deletes a single memory using the singular API endpoint.
  # Returns [deleted_ids, not_deleted_ids].
  def delete_single_memory(memory_id)
    copilot_api.delete_memory(owner: current_repository.owner_display_login, repo: current_repository.name, memory_id: memory_id, staging_env: staging_env)
    [[memory_id], []]
  end

  # Deletes multiple memories using the batch API endpoint.
  # Returns [deleted_ids, not_deleted_ids].
  def delete_memories_batch(memory_ids)
    result = copilot_api.delete_memories(owner: current_repository.owner_display_login, repo: current_repository.name, ids: memory_ids, staging_env: staging_env)
    [Array(result[:deleted]).compact, Array(result[:failed]).compact]
  end

  # Renders the appropriate response based on deletion outcomes.
  # - 204 No Content when all deletions succeeded
  # - 500 Internal Server Error when all deletions failed
  # - 200 OK with deleted/not_deleted IDs when partially successful
  def render_delete_result(memory_ids, deleted_ids, not_deleted_ids)
    metric_name = memory_ids.size > 1 ? "copilot_memory.delete_batch" : "copilot_memory.delete"

    if not_deleted_ids.empty?
      GitHub.logger.info("Copilot memory delete succeeded", {
        "gh.repo.id" => current_repository.id,
        "gh.repo.name" => current_repository.full_name,
        "gh.copilot_memory.deleted_count" => deleted_ids.size,
      })
      GitHub.dogstats.increment(metric_name, tags: ["result:success"])
      render json: {}, status: :no_content
    elsif not_deleted_ids.length == memory_ids.length
      GitHub.logger.error("Copilot memory delete failed: all IDs failed", {
        "gh.repo.id" => current_repository.id,
        "gh.repo.name" => current_repository.full_name,
        "gh.copilot_memory.failed_count" => not_deleted_ids.size,
        "gh.copilot_memory.failed_ids" => not_deleted_ids,
      })
      GitHub.dogstats.increment(metric_name, tags: ["result:all_failed"])
      render json: {}, status: :internal_server_error
    else
      GitHub.logger.info("Copilot memory delete partially succeeded", {
        "gh.repo.id" => current_repository.id,
        "gh.repo.name" => current_repository.full_name,
        "gh.copilot_memory.deleted_count" => deleted_ids.size,
        "gh.copilot_memory.failed_count" => not_deleted_ids.size,
      })
      GitHub.dogstats.increment(metric_name, tags: ["result:partial"])
      render json: { deleted_ids: deleted_ids, not_deleted_ids: not_deleted_ids }, status: :ok
    end
  end

  # Memoized Copilot API client authenticated with the current user's token.
  memoize def copilot_api
    token = CopilotSessions::CopilotApiToken.get_encrypted(user: T.must(current_user), entry_point: :copilot_memory, user_session: user_session)
    Copilot::User.copilot_api(user: T.must(current_user), integration_id: CopilotAPI::COPILOT_SWE_AGENT, token: token)
  end

  memoize def staging_env
    CopilotSweAgent::SweAgentPath.resolve_env(user: current_user, repository: current_repository)
  end
end
