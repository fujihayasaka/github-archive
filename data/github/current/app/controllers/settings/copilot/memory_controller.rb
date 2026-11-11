# typed: true
# frozen_string_literal: true

class Settings::Copilot::MemoryController < ApplicationController
  include Settings::ControllerMethods
  include ApplicationController::VerifiedFetchDependency
  include Api::Internal::Twirp::Copilot::Helpers
  include Copilot::MemoryBillingEntityDecoration

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Settings::Copilot::MemoryController#destroy",
  ].freeze

  allow_verified_fetch only: [:destroy]

  before_action :login_required
  before_action :dotcom_required
  before_action :copilot_memory_enabled?

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Authnd,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:index, :destroy]

  class IndexPayload < ReactPayload::Base
    def route_id
      "indexRoute"
    end

    def payload
      {
        memories: @memories,
        activeBillingEntity: @active_billing_entity,
        loadError: @load_error,
      }
    end

    def initialize(memories:, active_billing_entity:, load_error: false)
      @memories = memories
      @active_billing_entity = active_billing_entity
      @load_error = load_error
    end
  end

  def self.react_bundle_name
    "copilot-memory"
  end

  # GET /settings/copilot/memory
  # Fetches and renders the list of Copilot memories for the current user.
  def index
    load_error = false
    begin
      # We will fetch a large, but bounded number of memories to display in the UI.
      # Note: :results can be nil when the API returns a blank body, so we default to [].
      memories = copilot_api.get_top_user_memories(limit: 500, request_timeout_s: 2.0, staging_env: staging_env).fetch(:results, []) || []
      GitHub.logger.info("Copilot memory fetch succeeded", log_context.merge(
        "gh.copilot_memory.count" => memories.size,
      ))
      GitHub.dogstats.increment("copilot_memory.fetch", tags: ["result:success"])
    rescue CopilotAPI::NetworkError => e
      GitHub.logger.error("Copilot memory fetch failed: network/timeout error", log_context.merge(
        "gh.error.message" => e.message,
        "gh.error.class" => e.class.name,
      ))
      GitHub.dogstats.increment("copilot_memory.fetch", tags: ["result:error", "error_type:network"])
      memories = []
      load_error = true
    rescue CopilotAPI::UnauthorizedError => e
      GitHub.logger.error("Copilot memory fetch failed: unauthorized", log_context.merge(
        "gh.error.message" => e.message,
        "gh.error.class" => e.class.name,
      ))
      GitHub.dogstats.increment("copilot_memory.fetch", tags: ["result:error", "error_type:unauthorized"])
      memories = []
      load_error = true
    rescue CopilotAPI::NotFoundError => e
      GitHub.logger.error("Copilot memory fetch failed: not found (memory not enabled for user)", log_context.merge(
        "gh.error.message" => e.message,
        "gh.error.class" => e.class.name,
      ))
      GitHub.dogstats.increment("copilot_memory.fetch", tags: ["result:error", "error_type:not_found"])
      memories = []
      load_error = true
    rescue CopilotAPI::RateLimitError => e
      GitHub.logger.error("Copilot memory fetch failed: rate limited", log_context.merge(
        "gh.error.message" => e.message,
        "gh.error.class" => e.class.name,
      ))
      GitHub.dogstats.increment("copilot_memory.fetch", tags: ["result:error", "error_type:rate_limit"])
      memories = []
      load_error = true
    rescue CopilotAPI::Error => e
      GitHub.logger.error("Copilot memory fetch failed", log_context.merge(
        "gh.error.message" => e.message,
        "gh.error.class" => e.class.name,
      ))
      GitHub.dogstats.increment("copilot_memory.fetch", tags: ["result:error", "error_type:other"])
      memories = []
      load_error = true
    end

    payload = IndexPayload.new(
      memories: decorate_memories_with_billing_entity(memories, log_context:),
      active_billing_entity: active_billing_entity,
      load_error: load_error,
    )
    respond_with_react(
      title: "Copilot memory",
      payload: payload,
      page_data: { selected_link: :copilot_memory },
      layout: "user_settings",
    )
  end

  # DELETE /settings/copilot/memory
  # Deletes one or more user-scoped Copilot memories. Dispatches to the singular API endpoint
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
      GitHub.logger.error("Copilot memory delete failed: unexpected error", log_context.merge(
        "gh.error.message" => e.message,
        "gh.error.class" => e.class.name,
      ))
      GitHub.dogstats.increment("copilot_memory.delete", tags: ["result:error", "error_type:unexpected"])
      render json: {}, status: :internal_server_error
    end
  end

  # before_action guard that returns 404 unless the Copilot memory policy flag,
  # the user-scoped rollout flag, and the memory policy are all enabled.
  def copilot_memory_enabled? # rubocop:disable GitHub/UseRestfulActions
    copilot_user = current_copilot_user

    unless copilot_user &&
      FeatureFlag.vexi.enabled?("copilot_memory_enablement_policy", current_user_for_memory, default: false) &&
      Copilot::Policies::Memory.user_scoped_memory_available_for?(copilot_user) &&
      Copilot::Policies::Memory.effective_value(copilot_user) == "enabled"
      render_404
    end
  end

  private

  memoize def current_user_for_memory
    T.must_because(current_user) { "#login_required ensures non-nil" }
  end

  memoize def log_context
    {
      "gh.user.id" => current_user_for_memory.id,
      "gh.user.login" => current_user_for_memory.display_login,
    }
  end

  # Deletes a single memory using the singular API endpoint.
  # Returns [deleted_ids, not_deleted_ids].
  def delete_single_memory(memory_id)
    copilot_api.delete_user_memory(memory_id:, staging_env: staging_env)
    [[memory_id], []]
  end

  # Deletes multiple memories using the batch API endpoint.
  # Returns [deleted_ids, not_deleted_ids].
  def delete_memories_batch(memory_ids)
    result = copilot_api.delete_user_memories(ids: memory_ids, staging_env: staging_env)
    [Array(result[:deleted]).compact, Array(result[:failed]).compact]
  end

  # Renders the appropriate response based on deletion outcomes.
  # - 204 No Content when all deletions succeeded
  # - 500 Internal Server Error when all deletions failed
  # - 200 OK with deleted/not_deleted IDs when partially successful
  def render_delete_result(memory_ids, deleted_ids, not_deleted_ids)
    metric_name = memory_ids.size > 1 ? "copilot_memory.delete_batch" : "copilot_memory.delete"

    if not_deleted_ids.empty?
      GitHub.logger.info("Copilot memory delete succeeded", log_context.merge(
        "gh.copilot_memory.deleted_count" => deleted_ids.size,
      ))
      GitHub.dogstats.increment(metric_name, tags: ["result:success"])
      render json: {}, status: :no_content
    elsif not_deleted_ids.length == memory_ids.length
      GitHub.logger.error("Copilot memory delete failed: all IDs failed", log_context.merge(
        "gh.copilot_memory.failed_count" => not_deleted_ids.size,
        "gh.copilot_memory.failed_ids" => not_deleted_ids,
      ))
      GitHub.dogstats.increment(metric_name, tags: ["result:all_failed"])
      render json: {}, status: :internal_server_error
    else
      GitHub.logger.info("Copilot memory delete partially succeeded", log_context.merge(
        "gh.copilot_memory.deleted_count" => deleted_ids.size,
        "gh.copilot_memory.failed_count" => not_deleted_ids.size,
      ))
      GitHub.dogstats.increment(metric_name, tags: ["result:partial"])
      render json: { deleted_ids: deleted_ids, not_deleted_ids: not_deleted_ids }, status: :ok
    end
  end

  # Memoized Copilot API client authenticated with the current user's token.
  memoize def copilot_api
    token = CopilotSessions::CopilotApiToken.get_encrypted(user: current_user_for_memory, entry_point: :copilot_memory, user_session: user_session)
    Copilot::User.copilot_api(user: current_user_for_memory, integration_id: CopilotAPI::COPILOT_SWE_AGENT, token: token)
  end

  memoize def staging_env
    CopilotSweAgent::SweAgentPath.resolve_env(user: current_user_for_memory)
  end

  # Resolves the active billing entity for the current user and returns a descriptor hash suitable for rendering in the React payload.
  # Returns the chain of active billing entities, so enterprise and organizations if present.
  # Returns nil when the user has no resolvable billing entity (e.g. Copilot for Individuals) or when resolution fails for any reason.
  memoize def active_billing_entity
    copilot_user = current_copilot_user
    return nil unless copilot_user

    resolver = Copilot::BillingEntityResolver.new(copilot_user)
    result = resolver.resolve

    build_billing_entity_hash_from_resolver(result)
  rescue StandardError => e
    GitHub.logger.warn("Copilot memory: failed to resolve active billing entity", log_context.merge(
      "gh.error.message" => e.message,
      "gh.error.class" => e.class.name,
    ))
    GitHub.dogstats.increment("copilot_memory.resolve_billing_entity", tags: ["result:error"])
    nil
  end
end
