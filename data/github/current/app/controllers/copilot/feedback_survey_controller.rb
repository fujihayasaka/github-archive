# typed: true
# frozen_string_literal: true

class Copilot::FeedbackSurveyController < ApplicationController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:open, :dismiss]

  before_action :login_required
  before_action :parse_json_params

  def dismiss # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?
    return head :not_found unless GitHub.copilot_enabled?

    Copilot::FeedbackSurvey::dismiss_survey(current_user, params[:slug])

    head :ok
  end

  def open # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?
    return head :not_found unless GitHub.copilot_enabled?

    Copilot::FeedbackSurvey::opened_survey(current_user, params[:slug])

    head :ok
  end

  private

  def target_for_conditional_access
    current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
