# typed: strict
# frozen_string_literal: true

class Copilot::CodeReviewFixWithCopilotController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include Copilot::CodeReviewFixConcern

  before_action :login_required
  before_action :require_code_review_fix_with_copilot_enabled
  before_action :code_review_access_required
  before_action :require_copilot_swe_agent_enabled

  before_action :parse_json_params, only: [:create]
  allow_verified_fetch only: [:create]

  sig { void }
  def create
    pull_request = current_repository.issues.find_by_number(params[:pull].to_i).try(:pull_request) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    return head(:not_found) if pull_request.nil?

    review_references = params[:review_references] || []
    return head(:bad_request) if review_references.empty?

    create_pull_request = ActiveModel::Type::Boolean.new.cast(params[:create_pull_request]) || false
    return head(:bad_request) if create_pull_request.nil?

    fix_all = ActiveModel::Type::Boolean.new.cast(params[:fix_all]) || false
    additional_instructions = params[:additional_instructions].presence

    problem_statement = build_problem_statement(
      review_references: review_references,
      fix_all: fix_all,
      additional_instructions: additional_instructions,
    )
    return head(:bad_request) if problem_statement.blank?

    if Rails.env.development?
      Rails.logger.mine(problem_statement)
      render json: { task_id: "dev-001", task_url: "/dev" }, status: :created
      return
    end

    model = params[:model].presence
    task = create_code_review_fix_task(
      pull_request,
      problem_statement: problem_statement,
      create_pull_request: create_pull_request,
      entry_point: :code_review_fix_with_copilot,
      event_type: "code_review_fix_with_copilot",
      model: model,
    )
    task_url = repo_task_path(current_repository.owner, current_repository, task.id)
    render json: { task_id: task.id, task_url: task_url }, status: :created
  rescue CopilotSessions::CopilotApiToken::IntegrationUnavailableError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue CopilotAPI::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  sig { params(review_references: T::Array[String], fix_all: T::Boolean, additional_instructions: T.nilable(String)).returns(String) }
  def build_problem_statement(review_references: [], fix_all: false, additional_instructions: nil)
    feedback_reference =
      if fix_all
        "all comments in [this review thread](#{review_references.first})"
      elsif review_references.size > 1
        "only the following review comments: #{review_references.map { |ref| "[comment](#{ref})" }.join(", ")}"
      else
        "only [this review comment](#{review_references.first})"
      end

    reference_type = if fix_all
      "review thread"
    elsif review_references.size > 1
      "review comments"
    else
      "review comment"
    end

    parts = [
      "@copilot Fix the code for #{feedback_reference}.",
      "When a review comment includes a suggested change, apply the suggestion exactly unless the instructions in the 'Additional instructions' section below indicate otherwise.",
      "Do not make changes beyond what is described in the linked #{reference_type}, unless requested in the 'Additional instructions' section below.",
    ]

    if additional_instructions.present?
      quoted = additional_instructions.strip.gsub("\n", "\n> ")
      parts << "### Additional instructions:\n\n> #{quoted}"
    end

    parts.join("\n\n")
  end

  sig { void }
  def require_code_review_fix_with_copilot_enabled
    ccr_flag_enabled = FeatureFlag.vexi.enabled?(:ccr_implement_suggestion_refresh, current_user, default: false)
    unified_flag_enabled = FeatureFlag.vexi.enabled?(:unified_batch_pr_comments, current_user, default: false)
    render_404 unless ccr_flag_enabled || unified_flag_enabled
  end
end
