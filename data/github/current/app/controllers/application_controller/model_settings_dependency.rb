# typed: false
# frozen_string_literal: true

# Settings in here deal with things that use
# user facing model Configuration settings ("Advanced Settings")
# Other parts are in lib/github/config
module ApplicationController::ModelSettingsDependency
  extend ActiveSupport::Concern

  included do
    helper_method :user_can_create_organizations?
  end

  # Determines whether this user sees links for creating
  # organizations. Enterprise only.
  def user_can_create_organizations?
    # On GHES first run, the user (an enterprise owner), can always create organizations
    return true if GitHub.enterprise_first_run?
    return false unless logged_in?
    return false if current_user.is_enterprise_managed?
    !current_user.spammy? &&
      (current_user.site_admin? || GitHub.user_can_create_organizations?)
  end
end
