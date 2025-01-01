# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::ProxySecurityHeaderController < Stafftools::Businesses::BusinessBaseController
  def create
    begin
      if params[:value] == "1"
        this_business.enable_proxy_security_header(actor: current_user)
        flash[:notice] = "Proxy security header enabled."
      else
        this_business.disable_proxy_security_header(actor: current_user)
        flash[:notice] = "Proxy security header disabled."
      end
    rescue Configurable::ProxySecurityHeader::ProxySecurityHeaderError => error
      flash[:error] = error.message
    end

    redirect_to stafftools_enterprise_security_path(this_business)
  end
end
