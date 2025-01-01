# typed: true
# frozen_string_literal: true

class Settings::ProfileFeedVisibilityController < ApplicationController
  include Settings::ControllerMethods

  before_action :login_required
  before_action :require_xhr
  before_action :validate_params

  def update
    value = ActiveModel::Type::Boolean.new.cast(params[:profile_feed_visible])
    current_user.settings.set!(:user_profile_feed_visible, value)

    GlobalInstrumenter.instrument("profile_activity_tab.visibility_changed", {
      actor: current_user,
      visibility: value ? "everyone" : "me",
    })

    head :ok
  end

  private

  def validate_params
    head :not_found unless params[:user_id] == current_user.display_login
    head :not_found unless %w[true false].include?(params[:profile_feed_visible])
  end
end
