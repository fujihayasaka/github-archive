# typed: true
# frozen_string_literal: true

# Backend support of user interactions for SecurityCenter::SurveyComponent
class Users::SecurityCenter::SurveyController < ApplicationController

  before_action :login_required

  def destroy
    survey_id = params[:id]
    return redirect_to :back unless survey_id.present?

    dismissal_setting_key = SecurityCenter::SurveyComponent.dismissal_setting_key(survey_id: survey_id, user_id: current_user.id)
    SecurityCenter::KV.store.set(dismissal_setting_key, "true")
    redirect_to :back
  end

  private

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
