# typed: strict
# frozen_string_literal: true

class Issues::FeedbackController < ApplicationController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]

  before_action :login_required
  before_action :parse_json_params

  sig { void }
  def create
    return render(json: { success: false }, status: :unprocessable_entity) unless valid_feedback_payload?

    # Add request context for hydro subscription
    payload_with_context = feedback_payload.merge(request_context: GitHub.context.to_hash)
    GlobalInstrumenter.instrument("issues_react_feedback", payload_with_context)

    # Return only non-sensitive payload to client (without full request context)
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
    payload = feedback_params.to_h.transform_values { |v| v == "" ? nil : v }

    # Convert rating to integer since it comes from JSON as string
    if payload[:rating].present?
      payload[:rating] = payload[:rating].to_i
    end

    T.let(payload, T::Hash[Symbol, T.untyped])
  end

  sig { returns(T::Boolean) }
  def valid_feedback_payload?
    return false if feedback_payload[:content].present? && feedback_payload[:content].length > Hydro::EntitySerializer::ISSUES_REACT_FEEDBACK__CONTENT_MAX_LENGTH
    return false if feedback_payload[:rating].blank?

    # Delegate to serializer to ensure consistency
    Hydro::EntitySerializer.issues_react_feedback_rating(feedback_payload[:rating]) != :UNKNOWN
  end

  sig { returns(T.any(User, Symbol)) }
  def target_for_conditional_access
    return current_user if logged_in?

    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
