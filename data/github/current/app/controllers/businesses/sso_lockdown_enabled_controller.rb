# typed: true
# frozen_string_literal: true

class Businesses::SsoLockdownEnabledController < Businesses::BusinessController
  before_action :login_required
  before_action :write_enterprise_sso_required
  before_action :ensure_not_ghes

  def create
    if params[:value].blank? || params[:value] == "" || params[:value].nil?
      redirect_to :back
    elsif params[:value] == "1"
      this_business.enable_sso_lockdown(actor: current_user)
    else
      this_business.disable_sso_lockdown(actor: current_user)
    end
    redirect_to :back
  end

  private

  def ensure_not_ghes
    render_404 if GitHub.enterprise?
  end
end
