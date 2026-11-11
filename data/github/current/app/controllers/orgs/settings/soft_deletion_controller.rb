# typed: true
# frozen_string_literal: true

class Orgs::Settings::SoftDeletionController < Orgs::Controller
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch

  before_action :organization_admin_required

  def create
    DeleteToken.verify! current_user, this_organization, params[:dangerzone]

    business = this_organization.business
    cannot_delete_reason = this_organization.cannot_delete_reason(current_user)
    case cannot_delete_reason
    when :trusted_oauth_apps_owner
      flash[:error] = "#{this_organization.display_login} cannot be deleted. It's the owner of some trusted applications."
    when :sponsorable
      flash[:error] = "#{this_organization.display_login} cannot be deleted. It has a published Sponsors " \
        "profile that must be unpublished first."
    else
      if this_organization.has_any_trade_restrictions?
        flash[:trade_controls_organization_billing_error] = true
      else
        this_organization.soft_delete!(current_user)
        flash[:notice] = "#{this_organization.display_login} is being deleted."
      end
    end
  rescue DeleteToken::DangerZone => danger
    failbot StandardError.new("OrganizationsController.destroy failed - invalid CRSF token")
    GitHub.logger.error({ exception: danger, "code.function": "OrganizationsController.destroy" })
  ensure
    if request.xhr?
      head 200
    else
      redirect_to business.present? ? enterprise_organizations_path(business) : "/"
    end
  end
end
