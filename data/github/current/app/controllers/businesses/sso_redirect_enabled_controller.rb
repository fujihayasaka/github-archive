# typed: true
# frozen_string_literal: true

class Businesses::SsoRedirectEnabledController < Businesses::BusinessController
  before_action :login_required
  before_action :business_owner_required
  before_action :sudo_filter
  before_action :emu_business_required, only: %i[create]

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

  def create
    if params[:value] == "1"
      this_business.enable_sso_redirect(actor: current_user)
    else
      this_business.disable_sso_redirect(actor: current_user)
    end
    redirect_to :back
  end
end
