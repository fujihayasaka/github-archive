# typed: true
# frozen_string_literal: true

class Copilot::PreferencesController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required

  allow_verified_fetch only: [:update]

  def update
    success_message = "No preference was saved."

    new_copilot_dashboard_quota_notification_dismissed = params[:copilot_dashboard_quota_notification_dismissed]
    if new_copilot_dashboard_quota_notification_dismissed.present?
      current_user.settings.set!(:copilot_dashboard_quota_notification_dismissed, new_copilot_dashboard_quota_notification_dismissed)
      success_message = "Dashboard quota notification preference successfully saved."
    end

    copilot_editor_upsell_banner_dismissed = params[:copilot_editor_upsell_banner_dismissed]
    if copilot_editor_upsell_banner_dismissed.present?
      updated_value = ActiveModel::Type::Boolean.new.cast(copilot_editor_upsell_banner_dismissed)
      current_user.settings.set!(:copilot_editor_upsell_banner_dismissed, updated_value)
      success_message = "Editor upsell banner preference successfully saved."
    end

    if current_user.feature_enabled?(:copilot_ftp_settings_upgrade)
      copilot_free_user_checklist_dismissed = params[:copilot_free_user_checklist_dismissed]
      if copilot_free_user_checklist_dismissed.present?
        updated_value = ActiveModel::Type::Boolean.new.cast(copilot_free_user_checklist_dismissed)
        current_user.settings.set!(:copilot_free_user_checklist_dismissed, updated_value)
        success_message = "Free user checklist visibility preference successfully saved."
      end

      copilot_free_user_checklist = params[:copilot_free_user_checklist]
      if copilot_free_user_checklist.present?
        current_user.settings.set!(:copilot_free_user_checklist, copilot_free_user_checklist)
        success_message = "Free user checklist successfully saved."
      end
    end

    render json: { notice: success_message }
  end

  private

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    # This controller requires the user to be logged in, but this filter
    # gets called before `login_required`, so we have to handle the case
    # where `current_user` is `nil`.
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

end
