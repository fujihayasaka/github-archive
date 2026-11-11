# typed: true
# frozen_string_literal: true

class Copilot::SweAgent::FeedbackController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]

  before_action :require_logged_in_user
  before_action :require_feature_enabled

  FEEDBACK_OPTIONS = [
    { label: "The changes are not relevant to the task", value: "NOT_RELEVANT" },
    { label: "Copilot changed too much", value: "TOO_MUCH" },
    { label: "Copilot didn’t change enough", value: "TOO_LITTLE" },
    { label: "This change is not helpful at all", value: "NOT_HELPFUL" },
  ]

  def create
    # create a new hydro event in the product feedback category
    payload = feedback_params

    pull_request = current_repository.issues.find_by_number(payload[:id].to_i).try(:pull_request) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    head :bad_request and return if !pull_request
    pull_request_id = pull_request.id

    head :bad_request and return if payload[:feedback].upcase == "NEGATIVE" && payload[:feedback_choice].blank?
    head :bad_request and return if payload[:feedback_target].present? && !ALLOWED_TARGETS.include?(payload[:feedback_target])

    ::CopilotSweAgent::Helpers::instrument_swe_agent_feedback(
      request_id: GitHub.context[:request_id],
      organization_id: current_repository.organization&.id,
      repository_id: current_repository.id,
      pull_request_id: pull_request_id,
      feedback_target_id: payload[:comment_id],
      analytics_tracking_id: current_user.analytics_tracking_id,
      feedback: payload[:feedback],
      feedback_target: payload[:feedback_target],
      # Filter down to valid feedback options only
      feedback_choice: (payload[:feedback_choice] || []) & FEEDBACK_OPTIONS.pluck(:value),
      text_response: payload[:text_response],
    )

    # whether the feedback submission succeeds or not, return :ok
    render(json: payload, status: :created)
  rescue ActionController::UnpermittedParameters
    render(json: { success: false }, status: :unprocessable_entity)
  end

  private

  def feedback_params
    REQUIRED_FEEDBACK_PARAMS.each { |key| params.require(key) }
    params.permit(*FEEDBACK_PARAMS)
  end

  FEEDBACK_PARAMS = [
    # This is called "comment_id" because the feedback component assumes that name, however, we just reuse it for feedback_target_id.
    :comment_id, # the ID of the timeline comment or review comment, if that is the target.
    :feedback, # whether the feedback is positive or negative
    :user_id,  # the ID of the owner giving the feedback
    :repository, # repository name that is being used
    :id, # id is pull_request ID
    :feedback_target, # the type of feedback target (pull request / timeline comment / review comment)
    :text_response, # the raw text entered by the user (this must ONLY be emitted in a second Hydro event, marked restricted with different view permissions)
    feedback_choice: [], # for negative feedback, the reason for the negative feedback, selected from an enum
  ]

  REQUIRED_FEEDBACK_PARAMS = [
    :feedback,
    :user_id,
    :repository,
    :id,
  ]

  ALLOWED_TARGETS = %w(PR_BODY PR_TIMELINE_COMMENT PR_REVIEW_COMMENT)

  def require_logged_in_user
    render_404 unless logged_in?
  end

  def require_feature_enabled
    render_404 unless feature_enabled?
  end

  def feature_enabled?
    current_repository.copilot_swe_agent_enabled?(current_user)
  end

end
