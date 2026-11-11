# typed: true
# frozen_string_literal: true

class SshCertificateAuthorityExpirationController < ApplicationController
  before_action :login_required
  before_action :find_owner!
  before_action :owner_admin_required
  before_action :find_ca!
  before_action :sudo_filter

  def update
    if @ca.set_default_max_ssh_cert_lifetime
      flash[:notice] = "SSH certificate authority updated"
    else
      flash[:error] = "Error updating SSH certificate authority"
    end
    redirect_to owner_security_settings_path
  end

  private

  # Path to owner's security settings page.
  def owner_security_settings_path
    case owner
    when Organization
      settings_org_security_path(owner.display_login)
    when Business
      settings_security_enterprise_path(owner.slug)
    end
  end
  helper_method :owner_security_settings_path

  # Before action, checking that current user is admin of owner.
  def owner_admin_required
    return if owner.is_a?(Organization) && owner.adminable_by?(current_user)
    return if owner.is_a?(Business) && owner.owner?(current_user)
    render_404
  end

  # Before action that finds the CA we're working with by ID.
  def find_ca!
    raise ActiveRecord::RecordNotFound if ca_id_param.nil?
    @ca = owner.ssh_certificate_authorities.find_by_id!(ca_id_param)
  end

  # Finds the org/business we're handling CAs for.
  def owner # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @owner if defined?(@owner)

    @owner = if organization_login_param.present?
      Organization.where(login: organization_login_param).first
    elsif business_slug_param.present?
      Business.where(slug: business_slug_param).first
    end
  end

  # This runs as a before_action to ensure that an owner exists.
  def find_owner!
    raise ActiveRecord::RecordNotFound if owner.nil?
    owner
  end

  # Override for SAML enforcement.
  def target_for_conditional_access
    return :no_target_for_conditional_access unless owner # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    owner
  end

  def business_slug_param
    params[:slug].presence&.to_s
  end

  def organization_login_param
    params[:organization_id].presence&.to_s
  end

  def ca_id_param
    params[:id].presence&.to_i
  end
end
