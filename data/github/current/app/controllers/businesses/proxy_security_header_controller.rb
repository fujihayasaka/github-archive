# typed: true
# frozen_string_literal: true

class Businesses::ProxySecurityHeaderController < Businesses::BusinessController
  before_action :login_required
  before_action :sudo_filter

  def update
    begin
      if params[:enable_enterprise_access_restrictions] == "on"
        this_business.enable_proxy_security_header(actor: current_user)
        flash[:notice] = "Enterprise access restrictions via proxy headers have been enabled."
      else
        this_business.disable_proxy_security_header(actor: current_user)
        flash[:notice] = "Enterprise access restrictions via proxy headers have been disabled."
      end
    rescue Configurable::ProxySecurityHeader::ProxySecurityHeaderError => error
      flash[:error] = error.message
    end

    redirect_to settings_security_enterprise_path(this_business)
  end
end
