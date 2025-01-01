# typed: strict
# frozen_string_literal: true

class Copilot::CodeReviewFeedbackController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :feature_required

  allow_verified_fetch only: [:create]

  sig { void }
  def create
    organization = Organization.find_by(login: params[:user_id])
    pull_request_id = current_repository.issues.find_by_number(params[:pull].to_i).try(:pull_request)&.id

    PullRequests::Copilot::instrument_code_review_feedback(
      request_id: GitHub.context[:request_id],
      organization_id: organization&.id,
      repository_id: current_repository.id,
      pull_request_id: pull_request_id,
      comment_id: params[:comment_id],
      analytics_tracking_id: current_user.analytics_tracking_id,
      feedback: params[:feedback],
      feedback_choice: params[:feedback_choice],
      text_response: params[:text_response],
    )

    head :created
  end

  private

  sig { void }
  def feature_required
    access = PullRequests::Copilot::CodeReviewAccess.new(actor: current_user, current_repository: current_repository)
    render_404 unless access.can_create_review_request?
  end
end
