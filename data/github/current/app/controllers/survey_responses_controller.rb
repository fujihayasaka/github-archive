# typed: false
# frozen_string_literal: true

class SurveyResponsesController < ApplicationController

  include ControllerMethods::AnswerParams

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :login_required

  def update
    survey_slug = params[:slug]
    survey = Survey.find_by_slug(survey_slug)
    survey.save_answers(current_user, answer_params(survey))

    if request.xhr?
      render plain: "success"
    else
      if params[:return_to].present?
        safe_redirect_to params[:return_to], fallback: dashboard_path
      else
        redirect_to :back
      end
    end
  end
end
