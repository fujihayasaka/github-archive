# typed: true
# frozen_string_literal: true

module GlobalHeaderUserMenuHelper
  include HydroHelper

  extend T::Helpers
  requires_ancestor { ApplicationController }

  USER_MENU_CLICK_EVENT_TYPE = "global_header.user_menu_dropdown.click"

  module MenuOption
    YOUR_PROFILE        = :YOUR_PROFILE
    YOUR_REPOSITORIES   = :YOUR_REPOSITORIES
    YOUR_CODESPACES     = :YOUR_CODESPACES
    YOUR_ORGANIZATIONS  = :YOUR_ORGANIZATIONS
    YOUR_ENTERPRISES    = :YOUR_ENTERPRISES
    YOUR_PROJECTS       = :YOUR_PROJECTS
    YOUR_STARS          = :YOUR_STARS
    YOUR_GISTS          = :YOUR_GISTS
    GITHUB_APPS         = :GITHUB_APPS
    GITHUB_INSIGHTS     = :GITHUB_INSIGHTS
    UPGRADE             = :UPGRADE
    HELP                = :HELP
    SETTINGS            = :SETTINGS
    SIGN_OUT            = :SIGN_OUT
  end

  def your_profile_menu_hydro_attributes
    safe_data_attributes(
      hydro_click_tracking_attributes(
        USER_MENU_CLICK_EVENT_TYPE,
        request_url: request.original_url,
        target: MenuOption::YOUR_PROFILE,
      )
    )
  end

  def your_repositories_menu_hydro_attributes
    safe_data_attributes(
      hydro_click_tracking_attributes(
        USER_MENU_CLICK_EVENT_TYPE,
        request_url: request.original_url,
        target: MenuOption::YOUR_REPOSITORIES,
      )
    )
  end

  def your_organizations_menu_hydro_attributes
    safe_data_attributes(
      hydro_click_tracking_attributes(
        USER_MENU_CLICK_EVENT_TYPE,
        request_url: request.original_url,
        target: MenuOption::YOUR_ORGANIZATIONS,
      )
    )
  end

  def your_enterprises_menu_hydro_attributes
    safe_data_attributes(
      hydro_click_tracking_attributes(
        USER_MENU_CLICK_EVENT_TYPE,
        request_url: request.original_url,
        target: MenuOption::YOUR_ENTERPRISES,
      )
    )
  end

  def your_projects_menu_hydro_attributes
    safe_data_attributes(
      hydro_click_tracking_attributes(
        USER_MENU_CLICK_EVENT_TYPE,
        request_url: request.original_url,
        target: MenuOption::YOUR_PROJECTS,
      )
    )
  end

  def your_stars_menu_hydro_attributes
    safe_data_attributes(
      hydro_click_tracking_attributes(
        USER_MENU_CLICK_EVENT_TYPE,
        request_url: request.original_url,
        target: MenuOption::YOUR_STARS,
      )
    )
  end

  def your_gists_menu_hydro_attributes
    safe_data_attributes(
      hydro_click_tracking_attributes(
        USER_MENU_CLICK_EVENT_TYPE,
        request_url: request.original_url,
        target: MenuOption::YOUR_GISTS,
      )
    )
  end

  def github_insights_menu_hydro_attributes
    safe_data_attributes(
      hydro_click_tracking_attributes(
        USER_MENU_CLICK_EVENT_TYPE,
        request_url: request.original_url,
        target: MenuOption::GITHUB_INSIGHTS,
      )
    )
  end

  def upgrade_menu_hydro_attributes
    safe_data_attributes(
      hydro_click_tracking_attributes(
        USER_MENU_CLICK_EVENT_TYPE,
        request_url: request.original_url,
        target: MenuOption::UPGRADE,
      )
    )
  end

  def help_menu_hydro_attributes
    safe_data_attributes(
      hydro_click_tracking_attributes(
        USER_MENU_CLICK_EVENT_TYPE,
        request_url: request.original_url,
        target: MenuOption::HELP,
      )
    )
  end

  def settings_menu_hydro_attributes
    safe_data_attributes(
      hydro_click_tracking_attributes(
        USER_MENU_CLICK_EVENT_TYPE,
        request_url: request.original_url,
        target: MenuOption::SETTINGS,
      )
    )
  end

  def sign_out_menu_hydro_attributes
    safe_data_attributes(
      hydro_click_tracking_attributes(
        USER_MENU_CLICK_EVENT_TYPE,
        request_url: request.original_url,
        target: MenuOption::SIGN_OUT,
      )
    )
  end
end
