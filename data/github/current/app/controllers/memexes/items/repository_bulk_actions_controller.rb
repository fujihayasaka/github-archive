# typed: true
# frozen_string_literal: true

class Memexes::Items::RepositoryBulkActionsController < Memexes::Controller
  include Memexes::ThisRepositoryDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :require_this_memex
  before_action :user_has_write_access
  before_action :require_verified_email
  before_action :require_valid_count, only: [:create]
  before_action :require_valid_content_types, only: [:create]
  before_action :require_valid_search_query, only: [:create]
  before_action :require_repository, only: [:create]
  before_action :require_repository_access, only: [:create], if: :repository_specified?

  allow_verified_fetch only: [:create]

  MAX_ITEM_ADD_COUNT = 500
  RESULTS_PER_PAGE = 100
  ALLOWED_CONTENT_TYPES = %w[issue pr].freeze

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::Items::RepositoryBulkActionsController#create",
  ].freeze

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    ApplicationRecord::IssuesPullRequests, only: [:create]

  def create
    count = [bulk_add_params[:count].to_i, MAX_ITEM_ADD_COUNT].min
    content_types = bulk_add_params[:content_types] || []
    repository = this_repository

    # Create job status up front so we can return it immediately
    job_status = MemexBatchedBulkAddJob.create_job_status(this_memex.id, current_user.id)
    job_status.mark_as_initial_import!

    # Build search phrase - use q parameter if provided, otherwise default behavior
    search_phrase = if bulk_add_params[:q].present?
      helpers.replace_today_macro(bulk_add_params[:q])
    else
      # Default behavior: single content type narrows search
      phrase = "state:open"
      phrase += " is:#{content_types[0]}" if content_types.length == 1
      phrase
    end

    job_options = {
      actor_id: current_user.id,
      repository_id: repository&.id,
      count: count,
      search_phrase: search_phrase,
      request_context: GitHub.context.to_hash,
      user_session:,
    }

    MemexRepositoryBulkAddInitializerJob.perform_later(this_memex.id, job_status.id, **job_options)

    render json: { job: { url: job_status_url(job_status.id) } }
  end

  private

  def bulk_add_params
    underscored_params.permit(:memex_id, :repository_id, :count, :initial_import, :q, content_types: []).with_defaults(count: MAX_ITEM_ADD_COUNT)
  end

  def require_valid_count
    render_json_error(error: "Count must be positive", status: :unprocessable_entity) if bulk_add_params[:count].to_i < 1
  end

  def require_valid_content_types
    content_types = bulk_add_params[:content_types] || []

    # Enforce separation: either use q parameter OR content_types, but not both
    if bulk_add_params[:q].present? && content_types.any?
      return render_json_error(error: "Cannot specify both 'q' parameter and 'content_types'. Use 'q' for custom search syntax or 'content_types' for traditional filtering.", status: :unprocessable_entity)
    end

    # When using custom q parameter, content_types should be empty
    # When not using q parameter, content_types are required
    if content_types.empty? && bulk_add_params[:q].blank?
      return render_json_error(error: "Content types are required when not using custom search query", status: :unprocessable_entity)
    end

    invalid = content_types - ALLOWED_CONTENT_TYPES
    if invalid.any?
      render_json_error(error: "Invalid content types: #{invalid.join(', ')}", status: :unprocessable_entity)
    end
  end

  def require_valid_search_query
    return if bulk_add_params[:q].blank?

    if bulk_add_params[:q].length > 1000
      render_json_error(error: "Search query is too long", status: :unprocessable_entity)
    end
  end

  def require_repository
    return validate_custom_query_repository_scope if bulk_add_params[:q].present?
    return if bulk_add_params[:repository_id].present?

    render_json_error(error: "Repository is required", status: :unprocessable_entity)
  end

  def validate_custom_query_repository_scope
    if bulk_add_params[:repository_id].present?
      return render_json_error(
        error: "Cannot specify both 'q' parameter and 'repository_id'. Use 'q' for custom search syntax or 'repository_id' for traditional repository-scoped search.",
        status: :unprocessable_entity
      )
    end

    return unless multi_tenant_environment?

    repo_qualifiers = bulk_add_params[:q].scan(/\brepo:[^\s]+/)
    return if repo_qualifiers.one?

    render_json_error(error: repo_scope_error_message(repo_qualifiers), status: :unprocessable_entity)
  end

  def multi_tenant_environment?
    GitHub.multi_tenant_enterprise? || current_user&.is_enterprise_managed?
  end

  def repo_scope_error_message(repo_qualifiers)
    if repo_qualifiers.empty?
      "Cross-repository search is not supported in this environment. Please include 'repo:owner/name' in your search query."
    else
      "Multiple repository search is not supported in this environment. Please specify only one 'repo:owner/name' in your search query."
    end
  end

  def repository_specified?
    bulk_add_params[:repository_id].present?
  end

  def require_repository_access
    repo = this_repository
    render_404 unless repo && repo.readable_by?(current_user)
  end
end
