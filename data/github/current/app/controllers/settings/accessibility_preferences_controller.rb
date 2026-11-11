# typed: true
# frozen_string_literal: true

class Settings::AccessibilityPreferencesController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  CHARACTER_KEY_SETTINGS_KEY = :keyboard_shortcuts_preference.freeze
  ANIMATED_IMAGES_KEY = :motion_settings.freeze

  include Settings::ControllerMethods
  include OrganizationsHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  stylesheet_bundle :settings
  javascript_bundle :settings

  def show
    render "settings/accessibility_preferences/show", locals: {
      search_mode_options: CommandPalette::Hotkey.search_mode_form_options(is_mac: is_mac_platform?),
      commands_mode_options: CommandPalette::Hotkey.command_mode_form_options(is_mac: is_mac_platform?)
    }
  end

  def keyboard # rubocop:todo GitHub/UseRestfulActions
    if accessibilty_preferences_params[:keyboard_shortcuts_preference].present?
      current_user.settings.set!(CHARACTER_KEY_SETTINGS_KEY, accessibilty_preferences_params[:keyboard_shortcuts_preference])
    end

    search_shortcut = accessibilty_preferences_params[:search_mode_shortcut]
    command_shortcut = accessibilty_preferences_params[:command_mode_shortcut]

    if search_shortcut.present? && command_shortcut.present?
      if search_shortcut == command_shortcut && search_shortcut != CommandPalette::Hotkey::DISABLED_HOTKEY
        flash[:error] = "Search mode and command mode shortcuts cannot be the same."
      else
        current_user.settings.set!(:command_palette_open_hotkey, search_shortcut)
        current_user.settings.set!(:command_palette_open_command_mode_hotkey, command_shortcut)
      end
    end
  rescue SettingsCollection::InvalidUpdate => error
    flash[:error] = "Unable to save keyboard shortcuts preference. Please try again."
    title = "Unable to save ·"
  ensure
    unless flash[:error].present?
      flash[:notice] = "Keyboard shortcut preference successfully saved."
      title = "Setting saved ·"
    end

    flash[:page_title_prefix] = title

    redirect_to settings_accessibility_preferences_path
  end

  def link_underlines # rubocop:todo GitHub/UseRestfulActions
    current_user.settings.set!(:link_underlines, accessibilty_preferences_params[:link_underlines] == "true")
  rescue SettingsCollection::InvalidUpdate => error
    flash[:error] = "Unable to save link underline preferences. Please try again."
    title = "Unable to save ·"
  ensure
    unless flash[:error].present?
      flash[:notice] = "Link underline preferences successfully saved."
      title = "Setting saved ·"
    end

    flash[:page_title_prefix] = title

    redirect_to settings_accessibility_preferences_path
  end

  def hovercards_enabled # rubocop:todo GitHub/UseRestfulActions
    current_user.settings.set!(:hovercards_enabled, accessibilty_preferences_params[:hovercards_enabled])
  rescue SettingsCollection::InvalidUpdate => error
    flash[:error] = "Unable to save hovercard preferences. Please try again."
    title = "Unable to save ·"
  ensure
    unless flash[:error].present?
      flash[:notice] = "Hovercard preferences successfully saved."
      title = "Setting saved ·"
    end

    flash[:page_title_prefix] = title

    redirect_to settings_accessibility_preferences_path
  end

  def announcement_preference_hovercard # rubocop:todo GitHub/UseRestfulActions
    current_user.settings.set!(:announcement_preference_hovercard, accessibilty_preferences_params[:announcement_preference_hovercard])
  rescue SettingsCollection::InvalidUpdate => error
    flash[:error] = "Unable to save hovercard assistive technology hint preferences. Please try again."
    title = "Unable to save ·"
  ensure
    unless flash[:error].present?
      flash[:notice] = "Hovercard assistive technology hint preferences successfully saved."
      title = "Setting saved ·"
    end

    flash[:page_title_prefix] = title

    redirect_to settings_accessibility_preferences_path
  end

  def motion # rubocop:todo GitHub/UseRestfulActions
    current_user.settings.set!(:animated_images, accessibilty_preferences_params[:animated_images])
  rescue SettingsCollection::InvalidUpdate => error
    flash[:error] = "Unable to save motion preferences. Please try again."
    title = "Unable to save ·"
  ensure
    unless flash[:error].present?
      flash[:notice] = "Motion preferences successfully saved."
      title = "Setting saved ·"
    end

    flash[:page_title_prefix] = title

    redirect_to settings_accessibility_preferences_path
  end

  def paste_url_markdown # rubocop:todo GitHub/UseRestfulActions
    current_user.settings.set!(:paste_url_markdown, accessibilty_preferences_params[:paste_url_markdown] == "true")
  rescue SettingsCollection::InvalidUpdate => error
    flash[:error] = "Unable to save URL paste behavior preferences. Please try again."
    title = "Unable to save ·"
  ensure
    unless flash[:error].present?
      flash[:notice] = "Paste behavior preferences successfully saved."
      title = "Setting saved ·"
    end

    flash[:page_title_prefix] = title

    redirect_to settings_accessibility_preferences_path
  end

  private

  def accessibilty_preferences_params
    params
      .require(:user)
      .permit(:keyboard_shortcuts_preference, :link_underlines, :hovercards_enabled, :search_mode_shortcut, :command_mode_shortcut, :animated_images, :paste_url_markdown, :announcement_preference_hovercard)
  end

  def is_mac_platform?
    request&.user_agent&.match?(/Macintosh/)
  end
end
