# typed: true
# frozen_string_literal: true

class Settings::AppearancePreferences::FixedWidthFontsController < ApplicationController
  include OrganizationsHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:update]

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Settings::AppearancePreferences::FixedWidthFontsController#update"
  ].freeze

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  def update
    current_user.settings.set!(:use_fixed_width_font, use_fixed_width_font?)
    success_message = "Font preference successfully saved."

    if request.xhr?
      render json: { notice: success_message }
    else
      flash[:notice] = success_message
      redirect_to settings_appearance_preferences_path
    end
  end

  private

  def target_for_conditional_access
    # This controller requires the user to be logged in, but this filter
    # gets called before `login_required`, so we have to handle the case
    # where `current_user` is `nil`.
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def use_fixed_width_font?
    params[:use_fixed_width_font_preference] == "1"
  end
end
