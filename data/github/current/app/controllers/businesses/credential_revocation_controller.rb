# typed: true
# frozen_string_literal: true

class Businesses::CredentialRevocationController < Businesses::BusinessController
  # correct permission to revoke credentials required
  before_action :write_enterprise_credentials_required
  # only supported in GHEC and Proxima; not supported yet in GHES
  before_action :dotcom_required

  def destroy
    revoke_credentials_and_authorizations = get_revocation_type == :credentials_and_authorizations

    if revoke_credentials_and_authorizations && !this_business&.enterprise_managed_user_enabled?
      flash[:error] = "This action is only available for Enterprise Managed Users."
      redirect_to settings_security_enterprise_path(this_business)
      return
    end

    # Verify enterprise slug
    unless verify_slug
      flash[:error] = "Enterprise slug does not match."
      redirect_to settings_security_enterprise_path(this_business)
      return
    end

    RevokeEnterpriseCredentialAuthorizationsJob.perform_later(current_user.id, this_business.id, revoke_emu_credentials: revoke_credentials_and_authorizations)

    flash[:notice] = "Currently #{revoke_credentials_and_authorizations ? "deleting all keys and tokens" : "revoking SSO authorizations"} in your enterprise. You can view all affected credentials in the audit log."
    redirect_to settings_security_enterprise_path(this_business)
  end

  private

  def verify_slug
    params[:verify].present? && params[:verify].casecmp?(this_business.slug)
  end

  def get_revocation_type
    case params[:revocation_type]
    when "authorizations"
      :authorizations_only
    when "credentials_and_authorizations"
      :credentials_and_authorizations
    else
      :authorizations_only
    end
  end
end
