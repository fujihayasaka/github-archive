# typed: true
# frozen_string_literal: true

class Stafftools::ApplicationsController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists
  before_action :load_application

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Lodge,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Lodge,
    only: [:developers]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :developers],
    optional: true

  DEFAULT_TEMP_RATE_LIMIT_DURATION = 3

  layout :new_nav_layout
  private def new_nav_layout
    case action_name
    when "show", "user", "developers", "github"
      security_layout
    else
      "stafftools"
    end
  end

  def developers # rubocop:todo GitHub/UseRestfulActions
    @owned_apps = this_user.oauth_applications.paginate(page: params[:page])
    render "stafftools/applications/developers"
  end

  def github # rubocop:todo GitHub/UseRestfulActions
    @github_owned_oauth_apps = this_user.oauth_authorizations.github_owned.paginate(page: params[:page])
    render "stafftools/applications/github"
  end

  def user # rubocop:todo GitHub/UseRestfulActions
    if this_user.organization?
      @owned_apps = this_user.oauth_applications.paginate(page: params[:page])
      render "stafftools/applications/developers"
    else
      authorized_apps = this_user.oauth_authorizations.third_party.order("oauth_applications.name asc").paginate(page: params[:page])
      render "stafftools/applications/user", locals: { application_type: "oauth", authorized_apps: authorized_apps }
    end
  end

  def show
    render "stafftools/applications/show"
  end

  def update
    if params[:rate_limit].present?
      rate = params[:rate_limit].to_i
      if params[:temporary]
        duration = params[:duration]&.match?(/\A\d+\z/) && params[:duration] != "0" ? params[:duration].to_i : DEFAULT_TEMP_RATE_LIMIT_DURATION
        @app.set_temporary_rate_limit rate, duration.days
      else
        @app.rate_limit = rate
      end
      temporarily = " temporarily for #{duration} days" if params[:temporary]
      flash[:notice] = "Application rate limit set to #{rate}#{temporarily}"
    end

    @app.save!
    redirect_to :back
  end

  def enable # rubocop:todo GitHub/UseRestfulActions
    @app.state = :active
    @app.save!
    flash[:notice] = "Application reactivated"
    redirect_to :back
  end

  def suspend # rubocop:todo GitHub/UseRestfulActions
    @app.state = :suspended
    @app.save!
    flash[:notice] = "Application suspended"
    redirect_to :back
  end

  def update_creation_limit # rubocop:todo GitHub/UseRestfulActions
    this_user.set_custom_applications_limit(application_type: OauthApplication, limit: params[:creation_limit])

    flash[:notice] = "Creation limit updated successfully."
    redirect_to stafftools_user_applications_path(user_id: this_user.login)
  end

  private

  def load_application
    @app = OauthApplication.find_by(id: params[:id])
  end
end
