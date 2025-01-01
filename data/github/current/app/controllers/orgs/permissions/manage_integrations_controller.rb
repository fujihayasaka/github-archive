# typed: true
# frozen_string_literal: true

class Orgs::Permissions::ManageIntegrationsController < Orgs::Controller
  before_action :organization_admin_required, only: [:suggestions]
  before_action :sudo_filter, only: [:grant, :revoke]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Permissions,
    ApplicationRecord::Collab,
    only: [:suggestions]

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        render partial: "orgs/permissions/manage_integrations_suggestions",
          formats: :html,
          locals: {
            view: create_view_model(::Settings::Organization::ManageIntegrationsView,
              organization: this_organization,
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
    decision = ::Permissions::Enforcer.authorize(
      action: :grant_manage_organization_apps,
      actor: current_user,
      subject: this_organization,
    )

    if !decision.allow?
      flash[:error] = decision.reason
      return redirect_to :back
    end

    # check whether the action can be granted for this subject
    decision = ::Permissions::Enforcer.authorize(
      action: :grantable_manage_organization_apps,
      actor: potential_member,
      subject: this_organization,
    )
    if !decision.allow?
      flash[:error] = decision.reason
      return redirect_to :back
    end

    # Actually grant the permission
    result = grant_management_of_all_organization_integrations(
      user: potential_member,
      organization: this_organization,
      entry_point: :manage_integrations_controller_grant
    )

    if result.success?
      flash[:notice] = "Granted #{potential_member.display_login} permission to manage GitHub Apps owned by this organization"
    else
      flash[:error] = result.reason
    end

    this_organization.instrument_github_app_manager(potential_member, action: :grant) if result.success?
    redirect_to :back
  end

  def revoke # rubocop:todo GitHub/UseRestfulActions
    # TODO: Do this lookup in the Permissions::Authorizer
    # Don't worry about scoping this to the organization here; the Permissions service can handle that.
    potential_member = User.find_by_login(login_param)
    unless potential_member
      flash[:error] = "Can't revoke permission from that person"
      return redirect_to :back
    end

    unless current_user != potential_member && Apps::ManagementHelper.can_update_all_apps?(on: this_organization, actor: current_user)
      flash[:error] = "You do not have permission to edit this app"
      return redirect_to :back
    end

    result = revoke_management_of_all_organization_integrations(
      user: potential_member,
      organization: this_organization,
      entry_point: :manage_integrations_controller_revoke
    )

    if result.success?
      flash[:notice] = "Revoked #{potential_member.display_login}'s permission to manage GitHub Apps owned by this organization"
    else
      flash[:error] = result.reason
    end

    this_organization.instrument_github_app_manager(potential_member, action: :revoke) if result.success?
    redirect_to :back
  end

  private

  def login_param
    params.require(:user_login)
  end
end
