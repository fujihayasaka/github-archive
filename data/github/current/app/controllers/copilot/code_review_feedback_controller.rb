# typed: strict
# frozen_string_literal: true

class Copilot::CodeReviewFeedbackController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :code_review_access_required

  allow_verified_fetch only: [:create]

  sig { void }
  def create
    pull_request_id = current_repository.issues.find_by_number(params[:pull].to_i).try(:pull_request)&.id # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    return head :bad_request if pull_request_id.nil?

    custom_instructions_included = PullRequests::Copilot::CodeReviewComment.where(
      subject_id: params[:comment_id],
      subject_type: "PullRequestReviewComment"
    ).where.not(copilot_instruction_type: nil).exists?

    PullRequests::Copilot::instrument_code_review_feedback(
      request_id: GitHub.context[:request_id],
      organization_id: Organization.find_by(login: params[:user_id])&.id,
      repository_id: current_repository.id,
      pull_request_id: pull_request_id,
      comment_id: params[:comment_id],
      comment_identifier: PullRequestReviewComment.find_by(id: params[:comment_id])&.automated_review_comment&.resource_id,
      analytics_tracking_id: current_user.analytics_tracking_id,
      feedback: params[:feedback],
      feedback_choice: params[:feedback_choice],
      text_response: params[:text_response],
      custom_instructions_included: custom_instructions_included,
      copilot_access_type: current_copilot_user_v2.access_type,
      feedback_target: params[:feedback_target],
    )

    head :created
  end

  private

  sig { void }
  def code_review_access_required
    access = PullRequests::Copilot::CodeReviewAccess.new(actor: current_user, current_repository: current_repository, bypass_quota_check: true)
    render_404 unless access.can_create_review_request?
  end
end
