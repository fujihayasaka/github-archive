# typed: true
# frozen_string_literal: true

class Memexes::Items::RepositoryBulkActionsController < Memexes::Controller
  include Memexes::ThisRepositoryDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :require_this_memex
  before_action :user_has_write_access
  before_action :require_verified_email
  before_action :require_batched_bulk_add_job_flag, only: [:create]
  before_action :require_valid_count, only: [:create]
  before_action :require_valid_content_types, only: [:create]
  before_action :require_valid_search_query, only: [:create]
  before_action :require_repository, only: [:create]
  before_action :require_repository_access, only: [:create], if: :repository_specified?

  allow_verified_fetch only: [:create]

  MAX_ITEM_ADD_COUNT = 500
  RESULTS_PER_PAGE = 100

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
      bulk_add_params[:q]
    else
      # Default behavior: single content type narrows search
      phrase = "is:open"
      phrase += " is:#{content_types[0]}" if content_types.length == 1
      phrase
    end

    MemexRepositoryBulkAddInitializerJob.perform_later(
        this_memex.id,
        job_status.id,
        actor_id: current_user.id,
        repository_id: repository&.id,
        count: count,
        search_phrase: search_phrase,
        request_context: GitHub.context.to_hash,
      )

    render json: { job: { url: job_status_url(job_status.id) } }
  end

  private

  def bulk_add_params
    underscored_params.permit(:memex_id, :repository_id, :count, :initial_import, :q, content_types: []).with_defaults(count: MAX_ITEM_ADD_COUNT)
  end

  def require_batched_bulk_add_job_flag
    unless FeatureFlag.vexi.enabled?(:batched_memex_bulk_add_job, [current_user, this_memex.owner], default: false)
      render_404
    end
  end

  def require_valid_count
    render_json_error(error: "Count must be positive", status: :unprocessable_entity) if bulk_add_params[:count].to_i < 1
  end

  def require_valid_content_types
    content_types = bulk_add_params[:content_types] || []

    allowed = %w[issue pr]

    # Enforce separation: either use q parameter OR content_types, but not both
    if bulk_add_params[:q].present? && content_types.any?
      return render_json_error(error: "Cannot specify both 'q' parameter and 'content_types'. Use 'q' for custom search syntax or 'content_types' for traditional filtering.", status: :unprocessable_entity)
    end

    # When using custom q parameter, content_types should be empty
    # When not using q parameter, content_types are required
    if content_types.empty? && bulk_add_params[:q].blank?
      return render_json_error(error: "Content types are required when not using custom search query", status: :unprocessable_entity)
    end

    invalid = content_types - allowed
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
    # Enforce separation: either use q parameter OR repository_id, but not both
    if bulk_add_params[:q].present? && bulk_add_params[:repository_id].present?
      return render_json_error(error: "Cannot specify both 'q' parameter and 'repository_id'. Use 'q' for custom search syntax or 'repository_id' for traditional repository-scoped search.", status: :unprocessable_entity)
    end

    if bulk_add_params[:q].present?
      # Custom query mode: validate repository scope in query
      query = bulk_add_params[:q]
      repo_qualifiers = query.scan(/\brepo:[^\s]+/)

      # In MT/EMU environments, only single-repository search is supported
      if repo_qualifiers.length != 1 && (GitHub.multi_tenant_enterprise? || current_user&.is_enterprise_managed?)
        if repo_qualifiers.empty?
          error_message = "Cross-repository search is not supported in this environment. Please include 'repo:owner/name' in your search query."
        else
          error_message = "Multiple repository search is not supported in this environment. Please specify only one 'repo:owner/name' in your search query."
        end

        render_json_error(
          error: error_message,
          status: :unprocessable_entity
        )
      end
    elsif bulk_add_params[:repository_id].blank?
      # Traditional mode: repository_id is required
      render_json_error(error: "Repository is required", status: :unprocessable_entity)
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
