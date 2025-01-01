# typed: true
# frozen_string_literal: true

class Stafftools::OrganizationMemberships::TwoFactorRequirementController < StafftoolsController
  before_action :ensure_user_exists
  before_action :ensure_account_is_user

  def create
    org = Organization.find_by_login(params[:organization_membership_id])
    if org.can_two_factor_requirement_be_enabled?
      GitHub.dogstats.increment "organization", tags: ["action:enable_two_factor_requirement"]
      disallowed_methods = org.business&.insecure_two_factor_methods_disallowed? ? [Configurable::TwoFactorDisallowedMethods::INSECURE] : []
      EnforceTwoFactorRequirementOnOrganizationJob.perform_later(org, current_user, disallowed_methods: disallowed_methods)
      flash[:notice] = "Enabling two-factor authentication requirement."
    else
      flash[:error] = "Two-factor authentication requirement cannot be enabled. No organization admins have two-factor authentication enabled."
    end
    redirect_to stafftools_user_organization_memberships_path(this_user)
  end

  def destroy
    org = Organization.find_by_login(params[:organization_membership_id])
    GitHub.dogstats.increment "organization", tags: ["action:disable_two_factor_requirement"]

    org.disable_two_factor_requirement(log_event: true, actor: current_user)

    flash[:notice] = "Disabled two-factor authentication requirement."
    redirect_to stafftools_user_organization_memberships_path(this_user)
  end
end
