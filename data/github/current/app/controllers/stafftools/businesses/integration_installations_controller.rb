# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::IntegrationInstallationsController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required

  before_action :require_feature_enabled
  before_action :ensure_installation_exists, except: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:show, :index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :index], optional: true

  DEFAULT_TEMP_RATE_LIMIT_DURATION_IN_DAYS = 3

  def index
    installations = this_business.integration_installations.includes(:integration).
      joins(:integration).merge(Integration.not_for_github_connect).
      order("integrations.name asc").paginate(page: params[:page])

    view = create_view_model(Stafftools::Businesses::IntegrationInstallations::IndexView, installations: installations)
    render "stafftools/businesses/integration_installations/index", locals: { view: view }
  end

  def show
    view = create_view_model(
      Stafftools::Businesses::IntegrationInstallations::ShowView,
      installation: @installation,
      business: this_business,
    )
    render "stafftools/businesses/integration_installations/show", locals: { view: view }
  end

  def update
    if params[:rate_limit].present?
      rate = params[:rate_limit].to_i

      if params[:temporary]
        duration = params[:duration]&.match?(/\A\d+\z/) && params[:duration] != "0" ? params[:duration].to_i : DEFAULT_TEMP_RATE_LIMIT_DURATION_IN_DAYS
        @installation.set_temporary_rate_limit rate, duration.days
      else
        # Clear the temporary rate limit so the new rate limit
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
    redirect_to stafftools_enterprise_integration_installation_path(this_business, @installation)
  end

  def unsuspend # rubocop:todo GitHub/UseRestfulActions
    @installation.unsuspend!(user: current_user, staff_actor: true)
    @installation.reload

    flash[:notice] = "This installation has been unsuspended"
    redirect_to stafftools_enterprise_integration_installation_path(this_business, @installation)
  end

  def uninstall # rubocop:todo GitHub/UseRestfulActions
    UninstallIntegrationInstallationJob.perform_later(current_user.id, @installation.id, staff_actor: true)

    flash[:notice] = "A job has been queued to uninstall this integration installation. It may take a few minutes to complete."
    redirect_to stafftools_enterprise_path(this_business)
  end

  private

  def require_feature_enabled
    render_404 unless this_business.feature_enabled?(:enterprise_app_installation_management)
  end

  def ensure_installation_exists
    @installation = this_business.integration_installations.find_by(id: params[:id])
    render_404 unless @installation
  end
end
