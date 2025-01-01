# typed: true
# frozen_string_literal: true

class IpAllowlistEnabledController < ApplicationController
  before_action :login_required
  before_action :owner_required
  before_action :owner_admin_required
  before_action :sudo_filter

  def update
    if params[:enable_ip_allowlist] == "on"
      begin
        owner.enable_ip_allowlist \
          actor: current_user, actor_ip: request.remote_ip
        flash[:notice] = "IP allow list enabled."
      rescue Configurable::IpAllowlistEnabled::ActorLockoutError => error
        flash[:error] = error.message
      end
    else
      owner.disable_ip_allowlist(actor: current_user)
      flash[:notice] = "IP allow list disabled."
    end
    redirect_to redirect_path
  end

  private

  memoize def owner
    if params[:organization_id].present?
      Organization.find_by(login: params[:organization_id])
    elsif params[:slug].present?
      Business.find_by(slug: params[:slug])
    end
  end

  def owner_required
    render_404 unless owner
  end

  def owner_admin_required
    render_404 unless owner.adminable_by?(current_user)
  end

  def redirect_path
    if owner.is_a?(::Business)
      settings_security_enterprise_path(owner)
    elsif owner.is_a?(::Organization)
      settings_org_security_path(owner)
    end
  end

  # Safe because of :owner_required
  def target_for_conditional_access
    return :no_target_for_conditional_access unless owner # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    owner
  end
end
