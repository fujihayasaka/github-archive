# typed: true
# frozen_string_literal: true

class Stafftools::IntegrationsController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_owner_exists
  layout :security_layout
  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:authorizations]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
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
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :authorizations],
    optional: true

  def index
    @integrations = this_user.integrations.
      order("integrations.name asc").paginate(page: params[:page])

    render "stafftools/integrations/index"
  end

  def show
    render "stafftools/integrations/show", locals: { view: show_view }
  end

  def rename # rubocop:todo GitHub/UseRestfulActions
    integration.name = params[:name]
    if integration.save
      flash[:notice] = "Name successfully updated."
    else
      flash[:error] = integration.errors.full_messages.join(". ")
    end
    redirect_to stafftools_user_app_path(user_id: this_user.login, id: integration.slug)
  end

  def toggle_hook_active_status # rubocop:todo GitHub/UseRestfulActions
    integration.hook.toggle_active_status_from_stafftools(disable_reason: params[:disable_reason])
    flash[:notice] = "Okay, the webhook was successfully #{show_view.hook_active_status}."
    redirect_to :back
  end

  def authorizations # rubocop:todo GitHub/UseRestfulActions
    authorized_apps = this_user.oauth_authorizations.joins(:integration).order("integrations.name asc").paginate(page: params[:page])
    render "stafftools/applications/user", locals: { application_type: "integration", authorized_apps: authorized_apps }
  end

  def update_creation_limit # rubocop:todo GitHub/UseRestfulActions
    this_user.set_custom_applications_limit(application_type: Integration, limit: params[:creation_limit])

    flash[:notice] = "Creation limit updated successfully."
    redirect_to stafftools_user_apps_path(user_id: this_user.login)
  end

  def revoke_public_keys # rubocop:todo GitHub/UseRestfulActions
    RevokeIntegrationPublicKeysJob.perform_later(integration, Time.zone.now.to_i)

    flash[:notice] = "A job has been enqueued to revoke existing keys."
    redirect_to stafftools_user_apps_path(user_id: this_user.login)
  end

  def suspend # rubocop:todo GitHub/UseRestfulActions
    if integration.suspend(actor: current_user, reason: params[:reason])
      flash[:notice] = "Integration #{integration.slug} has been suspended."
    else
      flash[:error] = "App suspension has failed. Please try again."
    end

    redirect_to stafftools_user_app_path(user_id: this_user.login, id: integration.slug)
  end

  def unsuspend # rubocop:todo GitHub/UseRestfulActions
    if integration.unsuspend(actor: current_user)
      flash[:notice] = "Integration #{integration.slug} has been unsuspended."
    else
      flash[:error] = "App unsuspension has failed. Please try again."
    end

    redirect_to stafftools_user_app_path(user_id: this_user.login, id: integration.slug)
  end

  def suspend_all # rubocop:todo GitHub/UseRestfulActions
    if Integration.suspend_all_for_owner(actor: current_user, owner: this_user, reason: params[:reason])
      flash[:notice] = "All integrations owned by #{this_user.login} have been suspended."
    else
      flash[:error] = "App suspension has failed. Please try again."
    end
    redirect_to stafftools_user_apps_path(user_id: this_user.login)
  end

  def unsuspend_all # rubocop:todo GitHub/UseRestfulActions
    if Integration.unsuspend_all_for_owner(actor: current_user, owner: this_user)
      flash[:notice] = "All integrations owned by #{this_user.login} have been unsuspended."
    else
      flash[:error] = "App unsuspension has failed. Please try again."
    end
    redirect_to stafftools_user_apps_path(user_id: this_user.login)
  end

  private

  def show_view
    @show_view = Stafftools::Integrations::ShowView.new \
      integration: integration,
      hook_deliveries_query: params[:deliveries_q],
      query: params[:query]
  end

  def ensure_owner_exists
    render_404 unless this_user.present?
  end

  def integration # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @integration ||= this_user.integrations.find_by_slug!(params[:id])
  end
end
