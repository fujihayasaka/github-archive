# typed: true
# frozen_string_literal: true

class Businesses::EnterpriseInstallations::UserAccountsSyncController < Businesses::BusinessController
  before_action :business_owner_required

  def create
    if params[:enterprise_installation_user_accounts_upload_id]
      installation = nil
      if params[:enterprise_installation_id]
        installation = this_business.enterprise_installations.find_by \
          id: params[:enterprise_installation_id]
      end

      EnterpriseInstallation.synchronize_user_accounts_data \
        business: this_business,
        installation: installation,
        upload_id: params[:enterprise_installation_user_accounts_upload_id],
        actor: current_user

      flash[:notice] = "Enterprise Server license usage import started."
    else
      flash[:error] = "No license usage file was uploaded."
    end
    redirect_back fallback_location: settings_billing_enterprise_path(this_business)
  end
end
