# typed: true
# frozen_string_literal: true

class Orgs::Permissions::IntegrationsController < Orgs::Controller
  # TODO: make this part of the Permissions API check and send this to the
  # authorizer
  before_action :organization_admin_required
  before_action :sudo_filter, only: [:grant, :revoke]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Permissions,
    ApplicationRecord::Collab,
    only: [:suggestions]

  def managers # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      ::Settings::Organization::ManageIntegrationView,
      organization: this_organization,
      integration: this_integration,
    )
    render "orgs/permissions/integrations/managers", locals: { view: view }
  end

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        render partial: "orgs/permissions/manage_integrations_suggestions",
          formats: :html,
          locals: {
            view: create_view_model(::Settings::Organization::ManageIntegrationView,
              organization: this_organization,
              integration: this_integration,
              query: params[:q]
            )
          }
      end
    end
  end

  def grant # rubocop:todo GitHub/UseRestfulActions
    # TODO: Do this lookup in the Permissions::Authorizer
    # Don't worry about scoping this to the organization here; the Permissions service can handle that.
    potential_member = User.find_by_login(login_param)
    unless potential_member
      flash[:error] = "Can't grant permission to that person"
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

    # check whether the action can be granted to this author
    result = ::Permissions::Enforcer.authorize(
      action: :grantable_manage_app,
      actor: potential_member,
      subject: this_integration,
      context: { organization_id: this_organization.id, subject_owner_id: this_integration.owner_id },
    )
    unless result.allow?
      flash[:error] = "#{potential_member.display_login} is not authorized to be an app manager"
      return redirect_to :back
    end

    # Actually grant the permission
    result = grant_management_of_integration(
      user: potential_member,
      integration: this_integration,
      entry_point: :orgs_permissions_integration_controller_grant
    )

    if result.failure?
      flash[:error] = result.reason
    elsif result.pending?
      flash[:warn] = "Granting #{potential_member.display_login} permission to manage #{this_integration.name}"
    elsif result.success?
      flash[:notice] = "Granted #{potential_member.display_login} permission to manage #{this_integration.name}"
    end

    unless result.failure?
      this_integration.instrument_github_app_manager(potential_member, action: :grant)
    end

    redirect_to :back
  end

  def revoke # rubocop:todo GitHub/UseRestfulActions
    potential_member = User.find_by_login(login_param)
    unless potential_member
      flash[:error] = "Can't revoke permission from that person"
      return redirect_to :back
    end

    result = ::Permissions::Enforcer.authorize(
      action: :grant_manage_app,
      actor: current_user,
      subject: this_organization,
    )

    unless result.allow?
      flash[:error] = "You are not authorized to revoke app manager access for other users"
      return redirect_to :back
    end

    result = revoke_management_of_integration(
      user: potential_member,
      integration: this_integration,
      entry_point: :orgs_permissions_integration_controller_revoke
    )

    if result.failure?
      flash[:error] = result.reason
    elsif result.pending?
      flash[:warn] = "Revoking #{potential_member.display_login}'s permission to manage #{this_integration.name}"
    elsif result.success?
      flash[:notice] = "Revoked #{potential_member.display_login}'s permission to manage #{this_integration.name}"
    end

    unless result.failure?
      this_integration.instrument_github_app_manager(potential_member, action: :revoke)
    end

    redirect_to :back
  end

  private

  def this_integration # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @integration ||= this_organization.integrations.find_by!(slug: params[:id])
  end

  def login_param
    params.require(:user_login)
  end
end
