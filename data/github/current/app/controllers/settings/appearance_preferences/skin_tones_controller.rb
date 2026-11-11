# typed: true
# frozen_string_literal: true

class Settings::AppearancePreferences::SkinTonesController < ApplicationController
  include OrganizationsHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  # Skipping CAP because login_required
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def update
    profile_settings = current_user.profile_settings
    profile_settings.set_preferred_emoji_skin_tone = params[:emoji_skin_tone_preference]
    success_message = "Emoji skin tone preference successfully saved."

    if request.xhr?
      render json: { notice: success_message }
    else
      flash[:notice] = success_message
      redirect_to settings_appearance_preferences_path
    end
  end
end
