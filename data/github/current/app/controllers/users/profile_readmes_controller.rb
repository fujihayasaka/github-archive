# typed: true
# frozen_string_literal: true

class Users::ProfileReadmesController < Users::Controller
  include ApplicationController::VerifiedFetchDependency

  before_action :require_this_user
  before_action :ensure_this_user_is_current_user

  allow_verified_fetch only: [:create]

  README_FILENAME = "README.md"

  def create
    if config_repo.persisted?
      # If they aren't already, opt the current user into displaying their soon
      # to be created README on their profile to make this flow easier for new users
      unless current_user.profile_readme_opt_in?
        current_user.profile_readme_opt_in = true
        current_user.profile.save
      end

      blob_path = if config_repo.has_readme?
        blob_edit_path(config_repo.preferred_readme.path, config_repo.default_branch, config_repo)
      else
        blob_new_path("", config_repo.default_branch, config_repo) + "?" +
          {
            filename: README_FILENAME,
            path: "/",
            value: current_user.profile_readme_quick_start_template,
          }.to_query
      end

      redirect_to blob_path
    else
      flash[:error] = config_repo.errors.full_messages.join(", ")
      redirect_to user_path(current_user)
    end
  end

  private

  # Private: The profile configuration repository for the current user.
  #          If a user doesn't have one, we create one for them and return that.
  #
  # Returns a Repository.
  memoize def config_repo
    if current_user.has_configuration_repository?
      current_user.configuration_repository
    else
      current_user.create_configuration_repository(
        is_public: true,
        reflog_data: reflog_data,
        auto_init: false,
      )
    end
  end

  def reflog_data
    {
      real_ip: request.remote_ip,
      user_login: current_user.display_login,
      user_agent: request.user_agent,
      from: GitHub.context[:from],
      via: "create profile README",
    }
  end

  def target_for_conditional_access
    this_user
  end

  def ensure_this_user_is_current_user
    render_404 unless this_user == current_user
  end
end
