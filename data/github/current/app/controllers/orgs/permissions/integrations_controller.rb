# typed: true
# frozen_string_literal: true

class Orgs::Permissions::IntegrationsController < Orgs::Controller
  # TODO: make this part of the Permissions API check and send this to the
  # authorizer
  before_action :organization_admin_required
  before_action :sudo_filter, only: [:grant, :revoke]
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Permissions,
    ApplicationRecord::Collab,
    only: [:suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Permissions,
    ApplicationRecord::Collab,
    only: [:managers]

  def managers # rubocop:todo GitHub/UseRestfulActions
    render "orgs/permissions/integrations/managers", locals: { view: create_view_model(
      ::Settings::Organization::ManageIntegrationRolesView,
      organization: this_organization,
      integration: this_integration,
    ) }
  end

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        render partial: "orgs/permissions/manage_integrations_suggestions",
          formats: :html,
          locals: {
            view: create_view_model(::Settings::Organization::ManageIntegrationRolesView,
              organization: this_organization,
              integration: this_integration,
              query: params[:q],
              autocomplete_query_suggestions: autocomplete_query.suggestions
            )
          }
      end
    end
  end

  def grant # rubocop:todo GitHub/UseRestfulActions
    # TODO: Do this lookup in the Permissions::Authorizer
    # Don't worry about scoping this to the organization here; the Permissions service can handle that.

    unless potential_manager
      flash[:error] = "Can't grant permission to that #{potential_manager.class.name == "Team" ? 'team' : 'person'}"
      return redirect_to :back
    end

    # check whether the actor has the permission to grant this action for this
    # subject
    result = ::Permissions::Enforcer.authorize(
      action: :grant_manage_app,
      actor: current_user,
      subject: this_organization,
    )
    unless result.allow?
      flash[:error] = "You are not authorized to grant app manager access for other users"
      return redirect_to :back
    end

    # check whether the action can be granted to this actor
    allowed = if potential_manager.is_a?(BusinessTeam)
      Apps::ManagementHelper.business_team_ids_grantable_for_app_owner_role(on: this_integration).include?(potential_manager.id)
    elsif potential_manager.is_a?(Team)
      Apps::ManagementHelper.team_ids_grantable_for_app_owner_role(on: this_integration).include?(potential_manager.id)
    elsif potential_manager.is_a?(User)
      ::Permissions::Enforcer.authorize(
        action: :grantable_manage_app,
        actor: potential_manager,
        subject: this_integration,
        context: { organization_id: this_organization.id, subject_owner_id: this_integration.owner_id },
      ).allow?
    end

    unless allowed
      flash[:error] = "Not authorized to be an app manager"
      return redirect_to :back
    end

    # Actually grant the permission
    result = grant_management_of_integration(
      user: potential_manager,
      integration: this_integration,
      entry_point: :orgs_permissions_integration_controller_grant
    )

    name = potential_manager.is_a?(Team) ? potential_manager.name : potential_manager.display_login

    if result.success?
      flash[:notice] = "Granted #{name} permission to manage #{this_integration.name}"
    else
      flash[:error] = result.reason
    end

    this_integration.instrument_github_app_manager(potential_manager, action: :grant) if result.success?
    redirect_to :back
  end

  def revoke # rubocop:todo GitHub/UseRestfulActions
    unless potential_manager
      flash[:error] = "Can't revoke permission from that #{potential_manager.is_a?(Team) ? 'team' : 'person'}"
      return redirect_to :back
    end

    unless this_organization.adminable_by?(current_user)
      flash[:error] = "You are not authorized to revoke app manager access for other users"
      return redirect_to :back
    end

    result = revoke_management_of_integration(
      user: potential_manager,
      integration: this_integration,
      entry_point: :orgs_permissions_integration_controller_revoke
    )

    name = potential_manager.is_a?(Team) ? potential_manager.name : potential_manager.display_login
    if result.success?
      flash[:notice] = "Revoked #{name}'s permission to manage #{this_integration.name}"
    else
      flash[:error] = result.reason
    end

    this_integration.instrument_github_app_manager(potential_manager, action: :revoke) if result.success?
    redirect_to :back
  end

  private

  def this_integration # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @integration ||= this_organization.integrations.find_by!(slug: params[:id])
  end

  def login_param
    params.require(:user_login)
  end

  memoize def potential_manager
    manager_type = params[:manager_type]
    manager_id = params[:manager_id]

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
      organization: this_organization,
      include_teams: true
    )
  end
end
