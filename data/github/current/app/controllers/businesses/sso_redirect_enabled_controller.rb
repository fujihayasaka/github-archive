# typed: true
# frozen_string_literal: true

class Businesses::SsoRedirectEnabledController < Businesses::BusinessController
  before_action :login_required
  before_action :business_owner_required
  before_action :sudo_filter

  def update
    begin
      if params[:enable_sso_redirect] == "on"
        this_business.enable_sso_redirect(actor: current_user)
        flash[:notice] = "Automatic redirect enabled."
      else
        this_business.disable_sso_redirect(actor: current_user)
        flash[:notice] = "Automatic redirect disabled."
      end
    rescue Configurable::SsoRedirect::SsoRedirectError => error
      flash[:error] = error.message
    end
    redirect_to settings_security_enterprise_path(this_business)
  end
end
