# typed: true
# frozen_string_literal: true

class Site::Header::AppearanceSettingsComponent < ApplicationComponent

  # Show the appearance settings button in the header:
  # - If the feature flag is enabled (globally or for the logged-out user), and
  # - The user is logged-out (since logged-in users select increased-contrast themes by another mechanism)
  def visible?
    helpers.feature_enabled_globally_or_for_visitor?(feature_name: :appearance_settings_logged_out_users) && current_user.nil?
  end

end
