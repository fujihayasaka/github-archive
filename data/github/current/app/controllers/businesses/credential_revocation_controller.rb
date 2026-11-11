# typed: true
# frozen_string_literal: true

class Businesses::CredentialRevocationController < Businesses::BusinessController
  # correct permission to revoke credentials required
  before_action :write_enterprise_credentials_required
  # only supported in GHEC and Proxima; not supported yet in GHES
  before_action :not_ghes_required

  def destroy
    revoke_credentials_and_authorizations = get_revocation_type == :credentials_and_authorizations
    target_user_login = params[:target_user_login].presence
    single_user_mode = target_user_login.present? && single_user_revocation_enabled?

    if revoke_credentials_and_authorizations && !this_business&.enterprise_managed_user_enabled?
      flash[:error] = "This action is only available for Enterprise Managed Users."
      redirect_to settings_security_enterprise_path(this_business)
      return
    end

    # Verify confirmation text
    if single_user_mode
      unless verify_confirmation
        flash[:error] = "Confirmation text does not match."
        redirect_to settings_security_enterprise_path(this_business)
        return
      end
    else
      unless verify_slug
        flash[:error] = "Enterprise slug does not match."
        redirect_to settings_security_enterprise_path(this_business)
        return
      end
    end

    if single_user_mode
      target_user = User.find_by_login(target_user_login)
      unless target_user && this_business.business_user_account_for(target_user).present?
        flash[:error] = "User not found or is not a member of this enterprise."
        redirect_to settings_security_enterprise_path(this_business)
        return
      end

      if this_business.is_first_emu_owner?(user: target_user)
        flash[:error] = "The first EMU owner cannot be targeted for credential revocation."
        redirect_to settings_security_enterprise_path(this_business)
        return
      end

      RevokeUserCredentialAuthorizationsJob.perform_later(
        current_user.id,
        target_user.id,
        this_business.id,
        revoke_emu_credentials: revoke_credentials_and_authorizations
      )

      flash[:notice] = "Currently #{revoke_credentials_and_authorizations ? "deleting all keys and tokens" : "revoking SSO authorizations"} for #{target_user.display_login}. You can view all affected credentials in the audit log."
    else
      RevokeEnterpriseCredentialAuthorizationsJob.perform_later(current_user.id, this_business.id, revoke_emu_credentials: revoke_credentials_and_authorizations)

      flash[:notice] = "Currently #{revoke_credentials_and_authorizations ? "deleting all keys and tokens" : "revoking SSO authorizations"} in your enterprise. You can view all affected credentials in the audit log."
    end

    redirect_to settings_security_enterprise_path(this_business)
  end

  private

  def verify_slug
    params[:verify].present? && params[:verify].casecmp?(this_business.slug)
  end

  def single_user_revocation_enabled?
    FeatureFlag.vexi.enabled?(:credential_revocation_single_user, this_business, default: false)
  end

  def verify_confirmation
    expected = "#{this_business.slug} credentials"
    params[:verify].present? && params[:verify].casecmp?(expected)
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

  def not_ghes_required
    render_404 if GitHub.single_tenant_enterprise?
  end
end
