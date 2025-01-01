# typed: true
# frozen_string_literal: true

class Settings::ProfilesController < ApplicationController
  include Settings::ControllerMethods
  include SettingsHelper
  include OrganizationsHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access, only: :show
  before_action { @selected_link = :settings_user_profile }
  before_action(
    :ensure_specified_user_is_current_user,
    only: [
      :update_activity_overview_enabled,
      :update_profile_badges_preference,
    ],
  )
  skip_before_action( # rubocop:disable GitHub/DoNotSkipCapBeforeAction
    :perform_conditional_access_checks,
    only: [
      :update_activity_overview_enabled,
      :update_profile_badges_preference,
    ],
  )

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    if current_user.is_enterprise_managed?
      @emails = [current_user.profile_email]
    else
      @emails = current_user.possible_profile_emails

      if current_user.profile_email.present? && @emails.exclude?(current_user.profile_email)
        @emails << current_user.profile_email
      end
    end

    render "settings/user/profile"
  end

  def update_activity_overview_enabled # rubocop:todo GitHub/UseRestfulActions
    profile_settings = current_user.profile_settings
    profile_settings.activity_overview_enabled = params[:user][:activity_overview_enabled]
    current_user.dismiss_notice("org_scoped_activity_opt_in")

    if current_user.errors.any?
      flash[:error] = current_user.errors.full_messages.to_sentence
    else
      if profile_settings.activity_overview_enabled?
        flash[:contribution_graph_notice] = "Others will now see 'Activity overview' when they " \
                                            "view your profile."
      else
        flash[:contribution_graph_notice] = "The 'Activity overview' section will no longer " \
                                            "appear on your profile."
      end
    end

    redirect_to user_path(current_user, params: { focus_contribution_menu: "true" })
  end

  def update_profile_badges_preference # rubocop:todo GitHub/UseRestfulActions
    profile_settings = current_user.profile_settings

    unless params[:user][:pro_badge_enabled].nil?
      profile_settings.pro_badge_enabled = params[:user][:pro_badge_enabled]
    end

    if params[:user][:acv_badge_enabled].present?
      profile_settings.acv_badge_enabled = params[:user][:acv_badge_enabled]
    end

    if params[:user][:nasa_badge_enabled].present?
      profile_settings.nasa_badge_enabled = params[:user][:nasa_badge_enabled]
    end

    if params[:user][:achievements_enabled].present?
      profile_settings.achievements_enabled = params[:user][:achievements_enabled]
    end

    if params[:user][:achievements_projects_opt_out].present?
      profile_settings.all_private_projects_opted_out_of_achievements_tracking =
        params[:user][:achievements_projects_opt_out]
    end

    if current_user.errors.any?
      flash[:error] = current_user.errors.full_messages.to_sentence
    else
      flash[:notice] = "Profile updated successfully"
    end

    redirect_to settings_user_profile_path
  end

  private

  def ensure_specified_user_is_current_user
    render_404 unless params[:id].downcase == current_user.display_login.downcase
  end
end
