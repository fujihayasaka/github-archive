# typed: true
# frozen_string_literal: true

class SshCertificateAuthorityOwnerSettingsController < ApplicationController
  before_action :login_required
  before_action :owner_required
  before_action :owner_admin_required
  before_action :sudo_filter

  def update
    if params[:enable_ssh_cert_requirement] == "on"
      owner.enable_ssh_certificate_requirement(current_user)
    else
      owner.disable_ssh_certificate_requirement(current_user)
    end

    if owner.is_a?(Business) && owner.can_enable_ssh_certificate_user_owned_repo_access?
      if params[:enable_user_owned_repo_access] == "on"
        owner.enable_ssh_certificate_user_owned_repo_access(current_user)
      else
        owner.disable_ssh_certificate_user_owned_repo_access(current_user)
      end
    end

    flash[:notice] = "SSH certificate authority settings have been updated"
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

  # specify no target for CAP if there is no owner.. the route will 404 if this is the case (line 40)
  # if there _is_ an owner (enterprise or org), that'll be the target for CAP
  def target_for_conditional_access
    return :no_target_for_conditional_access unless owner # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    owner
  end
end
