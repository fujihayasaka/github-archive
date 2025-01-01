# typed: true
# frozen_string_literal: true

class GitHubModels::FeedbackController < ApplicationController
  include ApplicationController::VerifiedFetchDependency
  include GitHubModels::RenderDependency
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:create]
  before_action :parse_json_params, only: [:create]
  before_action :login_required, only: [:create]
  before_action :github_models_required

  def create
    feedback = params[:feedback]
    unless feedback.present? && feedback.dig(:model).present?
      return render status: 400, json: { message: "Invalid request" }
    end

    GlobalInstrumenter.instrument("github_models.feedback", {
      user: can_provide_additional_feedback? ? current_user : nil,
      feedback_type: feedback.dig(:satisfaction).to_i,
      feedback_choice: feedback.dig(:reasons).reject(&:empty?),
      content: can_provide_additional_feedback? ? feedback.dig(:feedbackText) : nil,
      model: feedback.dig(:model),
      can_be_contacted: can_provide_additional_feedback? ? feedback.dig(:contactConsent) == true : false,
    })

    redirect_to :back
  end

  private

  memoize def can_provide_additional_feedback?
    # If the current user belongs to an entity that is on a Copilot Business or Copilot Enterprise plan, we don't want to send any user data including free text and whether or not they can be contacted by us
    return false if current_user.nil?
    return false if T.must(current_copilot_user).has_cfb_access? || T.must(current_copilot_user).has_cfe_access?
    return false if T.must(current_user).organizations.any? { |org| Copilot::Organization.new(org).copilot_enabled? }
    return false if T.must(current_user).businesses.any? { |bus| Copilot::Business.new(bus).copilot_enabled? }
    true
  end

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
