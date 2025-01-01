# typed: true
# frozen_string_literal: true

class SshCertificateAuthoritiesController < ApplicationController
  before_action :login_required
  before_action :find_owner!
  before_action :active_enterprise_required, only: %i(new create)
  before_action :owner_admin_required
  before_action :find_ca!,              only: %i(destroy)
  before_action :sudo_filter, except: %i(new)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:new]

  def new
    render "ssh_certificate_authorities/new", locals: {
      ca: owner.ssh_certificate_authorities.build,
    }
  end

  def create
    ca = owner.ssh_certificate_authorities.new(ca_params)
    if ca.save
      flash[:notice] = "SSH certificate authority created"
      redirect_to owner_security_settings_path
    else
      flash[:error] = ca.errors.full_messages_for(:openssh_public_key).to_sentence
      render "ssh_certificate_authorities/new", locals: { ca: ca }
    end
  end

  def destroy
    if @ca.depended_on_for_cert_requirement?
      if owner.is_a?(Organization)
        flash[:error] = "Disable the 'Require SSH Certificate' feature before deleting the last CA"
      else
        if owner.ssh_certificate_requirement_enabled?
          flash[:error] = "Disable the 'Require SSH Certificate' feature before deleting the last CA"
        else
          # one of the business' orgs has the feature enabled
          flash[:error] = "Disable the 'Require SSH Certificate' feature on all organizations before deleting the last CA"
        end
      end
      return redirect_to owner_security_settings_path
    end

    if @ca.destroy
      flash[:notice] = "SSH certificate authority destroyed"
    else
      flash[:error] = "Error deleting SSH certificate authority"
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

  def ssh_certificate_authorities_path
    case owner
    when Organization
      ssh_certificate_authorities_organization_path(owner)
    when Business
      ssh_certificate_authorities_enterprise_path(owner)
    end
  end
  helper_method :ssh_certificate_authorities_path

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

  def ca_params
    params.require(:ssh_certificate_authority).permit(:openssh_public_key)
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

  memoize def this_business
    slug = params[:enterprise_slug] || params[:slug]
    ::Business.find_by(slug: slug)
  end

  def active_enterprise_required
    return unless business = Business.find_by(slug: params[:slug])
    return unless business.feature_enabled?(:hide_enterprise_features_for_expired_and_cancelled_trials)
    render_404 if business.trial_expired? || business.trial_cancelled?
  end
end
