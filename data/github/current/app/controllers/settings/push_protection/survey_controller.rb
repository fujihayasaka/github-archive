# typed: true
# frozen_string_literal: true

class Settings::PushProtection::SurveyController < ApplicationController
  before_action :login_required

  sig { void }
  def answer # rubocop:todo GitHub/UseRestfulActions
    if survey.taken_by?(current_user)
      render plain: "Already filled out", status: :bad_request
      return
    end

    answers = answer_params[:answers].to_h
    saved = survey.save_answers(current_user, answers)
    flash[:notice] = "Thank you for sharing your feedback!"
    safe_redirect_to referrer
  end

  sig { void }
  def dismiss # rubocop:todo GitHub/UseRestfulActions
    PushProtectionSurvey.hide_for(current_user)

    safe_redirect_to referrer
  end

  private

  sig { returns(T.any(User, Symbol)) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    current_user
  end

  sig { returns(Survey) }
  memoize def survey
    T.unsafe(Survey).find_by_slug(PushProtectionSurvey::SLUG)
  end

  sig { returns(ActionController::Parameters) }
  def answer_params
    # Because the answer format is {question_id => {"choice" => choice_id}} we need to create
    # a Hash with keys that match our question IDs. This allows us to filter input params.
    acceptable_input = survey.questions.pluck(:id).map { |id| [id.to_s, {}] }.to_h

    params.permit(:authenticity_token, :return_to, answers: acceptable_input)
  end

  sig { returns(T::Boolean) }
  def survey_already_taken?
    # If the Survey is missing, default to taken so that we don't render a broken page.
    return true if survey.blank?

    survey.taken_by?(current_user)
  end
end
