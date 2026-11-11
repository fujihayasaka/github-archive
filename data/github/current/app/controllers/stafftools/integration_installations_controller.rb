# typed: true
# frozen_string_literal: true

class Stafftools::IntegrationInstallationsController < StafftoolsController

  before_action :ensure_user_exists
  before_action :ensure_installation_exists, except: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Permissions,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :index], optional: true

  DEFAULT_TEMP_RATE_LIMIT_DURATION_IN_DAYS = 3

  layout :new_nav_layout

  def index
    installations = this_user.integration_installations.includes(:integration).
      order("integrations.name asc").paginate(page: params[:page])
    view = create_view_model(Stafftools::IntegrationInstallations::IndexView, installations: installations)
    render "stafftools/integration_installations/index", locals: { view: view }
  end

  def show
    repositories = @installation.repositories.includes(:mirror, :owner, :parent).paginate(page: current_page)

    view = create_view_model(
      Stafftools::IntegrationInstallations::ShowView,
      installation: @installation,
      repositories: repositories,
      user: this_user,
    )
    render "stafftools/integration_installations/show", locals: { view: view }
  end

  def update
    if params[:rate_limit].present?
      rate = params[:rate_limit].to_i

      if params[:temporary]
        duration = params[:duration]&.match?(/\A\d+\z/) && params[:duration] != "0" ? params[:duration].to_i : DEFAULT_TEMP_RATE_LIMIT_DURATION_IN_DAYS
        @installation.set_temporary_rate_limit rate, duration.days
      else
        # Clear the temportary rate limit so the new rate limit
        # is applied immediately
        @installation.update!(
          temporary_rate_limit:            nil,
          temporary_rate_limit_expires_at: nil,
          rate_limit:                      rate,
        )
      end

      temporarily = "temporarily " if params[:temporary]
      flash[:notice] = "Installation rate limit #{temporarily}set to #{rate}"
    end

    redirect_to :back
  end

  def suspend # rubocop:todo GitHub/UseRestfulActions
    @installation.suspend!(user: current_user, staff_actor: true)

    flash[:notice] = "This installation has been suspended"
    redirect_to stafftools_user_installation_path(@installation.target, @installation)
  end

  def unsuspend # rubocop:todo GitHub/UseRestfulActions
    @installation.unsuspend!(user: current_user, staff_actor: true)
    @installation.reload

    flash[:notice] = "This installation has been unsuspended"
    redirect_to stafftools_user_installation_path(@installation.target, @installation)
  end

  def uninstall # rubocop:todo GitHub/UseRestfulActions
    UninstallIntegrationInstallationJob.perform_later(current_user.id, @installation.id, staff_actor: true)

    flash[:notice] = "A job has been queued to uninstall this integration installation. It may take a few minutes to complete."
    redirect_to stafftools_user_path(@installation.target)
  end

  private

  def ensure_installation_exists
    @installation = this_user.integration_installations.find_by(id: params[:id])
    render_404 unless @installation
  end

  def new_nav_layout
    case this_user.site_admin_context
    when "organization"
      "layouts/stafftools/organization/security"
    when "user"
      "layouts/stafftools/user/security"
    end
  end
end
