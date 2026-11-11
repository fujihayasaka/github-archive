# typed: true
# frozen_string_literal: true

class Copilot::FeedbackController < Copilot::Chat::AbstractChatController
  allow_verified_fetch only: [:create]

  before_action :parse_json_params
  before_action :require_logged_in_user
  before_action :require_feature_enabled

  def create
    # create a new hydro event in the product feedback category
    payload = feedback_payload
    payload[:request_id] = GitHub.context[:request_id]

    render_422 and return if payload[:content].present? && payload[:content].length > 2000
    render_422 and return if payload[:rating].present? && !valid_rating?(payload[:rating])

    GlobalInstrumenter.instrument("copilot_user_feedback", payload)
    # whether the feedback submission succeeds or not, return :ok
    render(json: payload, status: :ok)
  rescue ActionController::UnpermittedParameters
    render(json: { success: false }, status: :unprocessable_entity)
  end

  private

  def feedback_payload
    feedback_params.to_h.slice(*FEEDBACK_PARAMS)
  end

  def valid_rating?(rating)
    return false if rating.blank?

    # Delegate to serializer to ensure consistency
    Hydro::EntitySerializer.copilot_feedback_rating(rating) != :UNKNOWN
  end

  def feedback_params
    params.permit(*FEEDBACK_PARAMS)
  end

  FEEDBACK_PARAMS = [
    :subject,
    :rating,
    :content,
    :hostname,
    :path,
    :mode,
  ]

  def require_logged_in_user
    render_404 unless logged_in?
  end

  def require_feature_enabled
    render_404 unless feature_enabled?
  end

  def feature_enabled?
    helpers.copilot_chat_enabled_for_current_user? && user_feature_enabled?(:copilot_chat_user_feedback)
  end

  def render_422
    render json: { success: false }, status: :unprocessable_entity
  end

  # No resource for CAP to require access to - this requires a licensed Copilot user with access to dotcom chat
  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return current_user if logged_in?
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
