# typed: true
# frozen_string_literal: true

class Orgs::DeparturesController < ApplicationController
  include OrganizationsHelper

  before_action :login_required
  after_action :customer_category_instrumentation

  # The following actions do not require conditional access checks:
  #
  # create - Does not access protected organization resources
  ACTIONS_EXCLUDED_FROM_CAP_CHECKS = %w(create)

  def create
    organization = Organization.find_by!(login: params[:organization_id])
    return render_404 unless current_user.affiliated_with_organization?(organization)

    begin
      if EnterpriseTeam.enabled_for_organizations?(business: organization.business)
        if organization.prevent_removal_of_scim_managed_user?(user: current_user, reason: :enterprise_team)
          flash[:notice] = "Can't leave #{organization.display_login} if you belong to a team managed by an enterprise team in this organization."
          return redirect_to :back
        end
      end

      if organization.prevent_removal_of_scim_managed_user?(user: current_user, reason: :derived)
        flash[:notice] = "Can’t leave #{organization.display_login} if you belong to an external group linked to a team in this organization."
      else
        organization.prevent_removal_of_last_admin!(current_user, "You can't remove the last admin")

        RemoveUserFromOrganizationJob.perform_later(organization.id, current_user.id)

        flash[:notice] = "You left #{organization.display_login}. It may take a few minutes to process."
      end
    rescue Organization::NoAdminsError
      flash[:notice] = "Can’t leave #{organization.display_login}. If you’re the last owner, delete the organization."
    end

    redirect_to :back
  end

  private

  def ip_allowlist_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    :yes
  end

  def external_conditional_access_policy_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    :yes
  end

  def two_factor_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    :yes
  end

  def require_active_external_identity_session?
    return false if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    true
  end
end
