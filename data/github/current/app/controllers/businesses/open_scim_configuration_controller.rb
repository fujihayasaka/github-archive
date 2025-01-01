# typed: true
# frozen_string_literal: true

class Businesses::OpenSCIMConfigurationController < Businesses::BusinessController
  before_action :login_required
  before_action :business_owner_required
  before_action :sudo_filter

  def update
    open_scim_configuration = params[:open_scim_configuration]&.to_s

    begin
      if open_scim_configuration == "on"
        this_business.enable_open_scim(actor: current_user)
        flash[:notice] = "Open SCIM enabled."
      else
        this_business.disable_open_scim(actor: current_user)
        flash[:notice] = "Open SCIM disabled."
      end
    rescue Configurable::OpenSCIM::OpenSCIMError => error
      flash[:error] = error.message
    end

    redirect_to settings_security_enterprise_path(this_business)
  end
end
