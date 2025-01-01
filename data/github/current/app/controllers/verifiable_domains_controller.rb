# typed: true
# frozen_string_literal: true

class VerifiableDomainsController < ApplicationController
  include BusinessesHelper
  include VerifiableDomainsHelper

  before_action :check_verified_domains_enabled
  before_action :login_required
  before_action :ensure_if_organization_required
  before_action :find_owner!
  before_action :owner_admin_required

  javascript_bundle "verified-domains"
  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:verification_steps]

  def index
    domains = VerifiableDomain.usable_for(owner).order("verified DESC, approved DESC, domain")
    render "verifiable_domains/index", locals: { owner: owner, verifiable_domains: domains }
  end

  def new
    render "verifiable_domains/new", locals: { owner: owner, profile_domains: owner_profile_domains }
  end

  def create
    domain_params = params.require(:verifiable_domain).permit(:domain)
    domain = owner.verifiable_domains.create(domain_params)

    if domain.errors.any?
      flash[:error] = domain.errors.full_messages.join(", ")
      render "verifiable_domains/new", locals: { owner: owner, profile_domains: owner_profile_domains }
    else
      redirect_to owner_domain_path_for_action(action: :verification_steps, owner: owner, domain: domain)
    end
  end

  def verification_steps # rubocop:todo GitHub/UseRestfulActions
    domain = owner.verifiable_domains.find(params[:id])

    if domain.verified? # can't re-verify a domain
      redirect_to owner_domain_path_for_action(owner: owner)
    else
      render "verifiable_domains/verification_steps", locals: { domain: domain }
    end
  end

  def regenerate_token # rubocop:todo GitHub/UseRestfulActions
    domain = owner.verifiable_domains.find(params[:id])
    domain.generate_verification_token
    if domain.errors.any?
      flash[:error] = domain.errors.full_messages.join(", ")
    end

    redirect_to owner_domain_path_for_action(action: :verification_steps, owner: owner, domain: domain)
  end

  def verify # rubocop:todo GitHub/UseRestfulActions
    domain = owner.verifiable_domains.find(params[:id])
    domain.verify(actor: current_user, request_timeout: GitHub.request_timeout(request.env))

    if domain.errors.any?
      flash[:error] = domain.errors.full_messages.join(", ")
      redirect_to owner_domain_path_for_action(action: :verification_steps, owner: owner, domain: domain)
    else
      flash[:notice] = "You verified the domain #{domain.domain}."
      redirect_to owner_domain_path_for_action(owner: owner)
    end
  end

  def approve # rubocop:todo GitHub/UseRestfulActions
    domain = owner.verifiable_domains.find(params[:id])

    if !domain.approve(actor: current_user)
      flash[:error] = domain.errors.full_messages.join(", ")
    else
      flash[:notice] = "You approved the domain #{domain.domain}."
    end
    redirect_to owner_domain_path_for_action(owner: owner)
  end

  def destroy
    domain = owner.verifiable_domains.find(params[:id])

    if owner.is_a?(Business) || domain.required_for_policy_enforcement?
      domain.disable_dependent_policies(actor: current_user)
    end

    if domain.destroy
      flash[:notice] = "The domain was deleted."
    else
      flash[:error] = domain.errors.full_messages.join(", ")
    end

    redirect_to owner_domain_path_for_action(owner: owner)
  end

  private

  def owner_profile_domains
    return [] unless owner.is_a?(Organization)

    [owner.profile_blog, owner.profile_email].reject(&:blank?).map do |domain|
      VerifiableDomain.normalize_domain(domain.to_s)
    end.uniq
  end

  def owner # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @owner if defined?(@owner)

    @owner = if organization_login_param.present?
      Organization.find_by!(login: organization_login_param)
    elsif business_slug_param.present?
      Business.find_by!(slug: business_slug_param)
    end
  end

  def find_owner!
    raise ActiveRecord::RecordNotFound if owner.nil?

    owner
  end

  # Before action that checks if owner is adminable by current user.
  def owner_admin_required
    return if owner.adminable_by?(current_user)

    render_404
  end

  # Before action that will 404 if verified domains aren't enabled.
  def check_verified_domains_enabled
    render_404 unless GitHub.verified_domains_enabled?
  end

  def business_slug_param
    params[:slug].presence&.to_s
  end

  def organization_login_param
    # Organization routes use a mixture of :org and :organization_id params:
    #  - index:    /organizations/:organization_id/settings/domains
    #  - the rest: /orgs/:org/domains/<domain-id>/action
    (params[:org].presence || params[:organization_id].presence)&.to_s
  end

  # Safe because :find_owner! will raise if owner is nil.
  def target_for_conditional_access
    return :no_target_for_conditional_access unless owner # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    owner
  end

  def this_business
    owner.is_a?(Business) ? owner : nil
  end
  helper_method :this_business

  def ensure_if_organization_required
    render_404 if owner.is_a?(Organization) && owner.deleted?
  end
end
