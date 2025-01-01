# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/ControllersShouldHaveTests
class Users::ConfigurationRepositoriesController < ApplicationController
  # rubocop:enable GitHub/ControllersShouldHaveTests
  before_action :login_required
  # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  skip_before_action :perform_conditional_access_checks, only: [:post_profile_readme_opt_in]
  # rubocop:enable GitHub/DoNotSkipCapBeforeAction

  def post_profile_readme_opt_in # rubocop:todo GitHub/UseRestfulActions
    current_user.profile_readme_opt_in = true
    current_user.profile.save!

    redirect_to opt_in_redirect_location
  end

  private

  def opt_in_redirect_location
    config_repo = current_user.configuration_repository
    return user_path current_user if config_repo.nil?

    if config_repo.private?
      # Clicked on "Update now" on config_repo files overview page.
      return edit_repository_path(current_user,
                                  config_repo,
                                  return_to: repository_path(config_repo))
    end

    # Clicked on "Share to Profile" on config_repo files overview page.
    if current_user.profile_readme.nil?
      flash[:notice] = "You've successfully shared your profile README!"
      return repository_path(config_repo)
    end

    user_path current_user
  end
end
