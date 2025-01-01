# typed: strict
# frozen_string_literal: true

class Copilot::CodeReviewFeedbackController < AbstractRepositoryController
  extend T::Sig

  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :feature_required

  allow_verified_fetch only: [:create]

  sig { void }
  def create
    organization = Organization.find_by(login: params[:user_id])
    pull_request_id = current_repository.issues.find_by_number(params[:pull].to_i).try(:pull_request)&.id

    context = {
      request_id: GitHub.context[:request_id],
      organization_id: organization&.id,
      repository_id: current_repository.id,
      pull_request_id: pull_request_id,
      comment_id: params[:comment_id],
      analytics_tracking_id: current_user.analytics_tracking_id,
    }

    payload = { type: params[:feedback] }
    GlobalInstrumenter.instrument("copilot.reviews.v0.Feedback", payload.merge(context))

    if params[:feedback_choice].present? || params[:text_response].present?
      restricted_payload = { feedback_choice: params[:feedback_choice], text_response: params[:text_response] }
      GlobalInstrumenter.instrument("copilot.reviews.v0.RestrictedFeedback", restricted_payload.merge(context))
    end

    head :created
  end

  private

  sig { void }
  def feature_required
    access = PullRequests::Copilot::CodeReviewAccess.new(actor: current_user, current_repository: current_repository)
    render_404 unless access.can_request_via_button? || access.can_create_review_request?
  end
end
