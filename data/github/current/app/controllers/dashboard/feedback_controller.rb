# typed: strict
# frozen_string_literal: true

class Dashboard::FeedbackController < ApplicationController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]

  before_action :login_required
  before_action :parse_json_params

  sig { void }
  def create
    return render_422 unless valid_payload?

    GlobalInstrumenter.instrument("dashboard.feedback", feedback_payload)
    # whether the feedback submission succeeds or not, return :ok
    render(json: feedback_payload, status: :ok)
  rescue ActionController::UnpermittedParameters
    render(json: { success: false }, status: :unprocessable_entity)
  end

  private

  FEEDBACK_PARAMS = [
    :subject,
    :rating,
    :content,
    :hostname,
    :path,
  ]

  sig { returns(ActionController::Parameters) }
  def feedback_params
    params.permit(*FEEDBACK_PARAMS)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize def feedback_payload
    T.let(
      feedback_params.to_h.merge(request_id: GitHub.context[:request_id]),
      T::Hash[Symbol, T.untyped]
    )
  end

  sig { returns(T::Boolean) }
  def valid_payload?
    return false if feedback_payload[:content].present? && feedback_payload[:content].length > 2000
    return false if feedback_payload[:rating].blank?

    # Delegate to serializer to ensure consistency
    Hydro::EntitySerializer.dashboard_feedback_rating(feedback_payload[:rating]) != :UNKNOWN
  end

  sig { void }
  def render_422
    render(json: { success: false }, status: :unprocessable_entity)
  end

  sig { returns(T.any(User, Symbol)) }
  def target_for_conditional_access
    return current_user if logged_in?

    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
