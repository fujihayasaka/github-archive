# typed: true
# frozen_string_literal: true

class Businesses::Permissions::IntegrationsController < Businesses::BusinessController
  # TODO: make this part of the Permissions API check and send this to the
  # authorizer
  before_action :business_required
  before_action :business_admin_required
  before_action :sudo_filter, only: [:create, :destroy]
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Permissions,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:managers]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Permissions,
    ApplicationRecord::Collab,
    only: [:suggestions]

  def managers # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      Businesses::ManageIntegrationRolesView,
      business: this_business,
      integration: this_integration,
    )

    render "businesses/permissions/integrations/managers", locals: { view: view }
  end

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        render partial: "businesses/permissions/integrations/manage_integrations_suggestions",
          formats: :html,
          locals: {
            view: create_view_model(Businesses::ManageIntegrationRolesView,
              business: this_business,
              integration: this_integration,
              query: params[:q],
            )
          }
      end
    end
  end

  def create
    unless potential_manager
      flash[:error] = "Can't grant permission because the manager is invalid or missing"
      return redirect_back(fallback_location: settings_app_enterprise_path(this_business, this_integration))
    end

    if manager_type == "BusinessTeam" && !this_business.erp_feature_enabled?(:enterprise_teams_crud)
      flash[:error] = "Enterprise teams are not enabled for this enterprise."
      return redirect_back(fallback_location: settings_app_enterprise_path(this_business, this_integration))
    end

    # TODO: Add authzd policy rather than using adminable.
    unless this_business.adminable_by?(current_user)
      flash[:error] = "You are not authorized to grant app manager access for other users"
      return redirect_back(fallback_location: settings_app_enterprise_path(this_business, this_integration))
    end

    # check whether the action can be granted to this actor
    role_can_be_granted_to_user = if potential_manager.is_a?(BusinessTeam)
      Apps::ManagementHelper.business_team_ids_grantable_for_app_owner_role(on: this_integration).include?(potential_manager.id)
    elsif potential_manager.is_a?(User)
      Apps::ManagementHelper.user_ids_grantable_for_app_owner_role(on: this_integration).include?(potential_manager.id)
    end

    unless role_can_be_granted_to_user
      flash[:error] = "Not authorized to be an app manager"
      return redirect_back(fallback_location: settings_app_enterprise_path(this_business, this_integration))
    end

    # Actually grant the permission
    result = helpers.grant_management_of_integration(
      user: potential_manager,
      integration: this_integration,
      entry_point: :businesses_permissions_integration_controller_grant
    )

    name = potential_manager.is_a?(Team) ? potential_manager.name : potential_manager.display_login

    if result.success?
      flash[:notice] = "Granted #{name} permission to manage #{this_integration.name}"
    else
      flash[:error] = result.reason
    end

    this_integration.instrument_github_app_manager(potential_manager, action: :grant) if result.success?
    redirect_back(fallback_location: settings_app_enterprise_path(this_business, this_integration))
  end

  def destroy
    unless potential_manager
      flash[:error] = "Can't revoke permission from that #{potential_manager.is_a?(Team) ? 'team' : 'person'}"
      return redirect_back(fallback_location: settings_app_enterprise_path(this_business, this_integration))
    end

    unless this_business.adminable_by?(current_user)
      flash[:error] = "You are not authorized to revoke app manager access for other users"
      return redirect_back(fallback_location: settings_app_enterprise_path(this_business, this_integration))
    end

    result = helpers.revoke_management_of_integration(
      user: potential_manager,
      integration: this_integration,
      entry_point: :businesses_permissions_integration_controller_revoke
    )

    name = potential_manager.is_a?(Team) ? potential_manager.name : potential_manager.display_login
    if result.success?
      flash[:notice] = "Revoked #{name}'s permission to manage #{this_integration.name}"
    else
      flash[:error] = result.reason
    end

    this_integration.instrument_github_app_manager(potential_manager, action: :revoke) if result.success?
    redirect_back(fallback_location: settings_app_enterprise_path(this_business, this_integration))
  end

  private

  def this_integration # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @integration ||= this_business.integrations.find_by!(slug: params[:id])
  end

  memoize def potential_manager
    case manager_type
    when "User"
      User.find_by(id: manager_id)
    when "Team"
      Team.find_by(id: manager_id)
    when "BusinessTeam"
      BusinessTeam.find_by(id: manager_id)
    else
      nil
    end
  end

  memoize def autocomplete_query
    AutocompleteQuery.new(
      current_user,
      params[:q],
      business: this_business,
      include_teams: true
    )
  end

  def business_admin_required
    render_404 unless this_business&.adminable_by?(current_user)
  end

  memoize def this_business
    slug = params[:enterprise_slug] || params[:slug]
    ::Business.find_by(slug: slug)
  end

  def manager_type
    params[:manager_type]
  end

  def manager_id
    params[:manager_id]
  end

  def business_required
    render_404 unless this_business
  end
end
