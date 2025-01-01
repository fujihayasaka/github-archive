# typed: true
# frozen_string_literal: true

class Api::Blackbird < Api::App
  include BlackbirdIndexHelper

  rate_limit_as Api::RateLimitConfiguration::CODE_SEARCH_FAMILY

  # Check if semantic search is available for a single repository
  get "/repositories/:repository_id/copilot_internal/embeddings_index", operation_id: :internal do
    @route_owner = "@github/code-search-reviewers"
    repo = find_repo!

    control_access :read_repo_code_search_status,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if current_user.feature_enabled?(:blackbird_require_valid_copilot_license)
      deliver_error!(404) unless copilot_user.has_copilot_access?
    end

    if current_integration&.feature_enabled?(:blackbird_disallow_integration_status_checks)
      deliver_error!(404)
    end

    resp = Search::Blackbird::Client.get_repository_status([repo.id])
    if resp.error
      err = T.must(resp.error)
      GitHub.logger.error("blackbird get_repository_status failed", "blackbird.error.code": err.code, "blackbird.error.msg": err.msg)
      deliver_error!(Twirp::ERROR_CODES_TO_HTTP_STATUS[err.code] || 503, message: err.msg)
    end

    repo_status = T.must(resp.data.repositories.first)
    semantic_indexing_enabled = CopilotIndexedRepositories.exists?(repository: repo.id)

    deliver_raw({
      lexical_search_ok: repo_status.lexical_search_ok,
      lexical_commit_sha: repo_status.lexical_commit_sha,
      semantic_code_search_ok: repo_status.semantic_code_search_ok,
      semantic_doc_search_ok: repo_status.semantic_doc_search_ok,
      semantic_commit_sha: repo_status.semantic_commit_sha,
      bm25_search_ok: repo_status.bm25_search_ok,
      can_index: can_index_embeddings_status(current_user, repo),
      semantic_indexing_enabled:,
    })
  end

  post "/repositories/:repository_id/copilot_internal/embeddings_index", operation_id: :internal do
    @route_owner = "@github/code-search-reviewers"
    repo = find_repo!

    # TODO: Make a :write_repo_code_search_status role (trigger_embeddings_indexing handles this manually right now).
    control_access :read_repo_code_search_status,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive(Hash, required: false) || {}
    if !!data["auto"] && !current_user.feature_enabled?(:blackbird_auto_embeddings_indexing)
      deliver_error!(503, message: "auto embeddings indexing is not enabled right now")
    end

    status = trigger_embeddings_indexing(current_user, repo, index_code: true, index_docs: false)

    if status != :ok
      # Quota-exhausted doesn't have a specific status code, so we need to handle it separately
      deliver_error!(403) if status == :quota_exhausted
      # Convert the status to a status code
      status_code = Rack::Utils::SYMBOL_TO_STATUS_CODE[status]
      deliver_error!(status_code)
    end

    if Copilot::Public::User::new(current_user).has_ci_access?
      current_count = current_user.settings.get(:copilot_indexed_repo_count)
      current_user.settings.set!(:copilot_indexed_repo_count, current_count + 1)
    end

    deliver_empty(status: 201)
  end

  def copilot_user
    @copilot_user ||= Copilot::Public::User.new(current_user)
  end
end
