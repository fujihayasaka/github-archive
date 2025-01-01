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
  before_action :require_this_repository, only: [:create]

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
    content_types = bulk_add_params[:content_types]
    repository = T.must(this_repository)

    # Create job status up front so we can return it immediately
    job_status = MemexBatchedBulkAddJob.create_job_status(this_memex.id, current_user.id)

    # Build search phrase here (single content type narrows search)
    search_phrase = "is:open"
    search_phrase += " is:#{content_types[0]}" if content_types.length == 1

    MemexRepositoryBulkAddInitializerJob.perform_later(
        this_memex.id,
        job_status.id,
        actor_id: current_user.id,
        repository_id: repository.id,
        count: count,
        search_phrase: search_phrase,
        request_context: GitHub.context.to_hash,
      )

    render json: { job: { url: job_status_url(job_status.id) } }
  end

  private

  def bulk_add_params
    underscored_params.permit(:memex_id, :repository_id, :count, content_types: []).with_defaults(count: MAX_ITEM_ADD_COUNT)
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
    content_types = bulk_add_params[:content_types]

    allowed = %w[issue pr]

    if content_types.empty?
      return render_json_error(error: "Content types are required", status: :unprocessable_entity)
    end

    invalid = content_types - allowed
    if invalid.any?
      render_json_error(error: "Invalid content types: #{invalid.join(', ')}", status: :unprocessable_entity)
    end
  end
end
