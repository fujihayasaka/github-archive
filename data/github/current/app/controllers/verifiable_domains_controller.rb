# typed: true
# frozen_string_literal: true

class VerifiableDomainsController < ApplicationController
  include VerifiableDomainsControllerMethods

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
      flash.now[:error] = domain.errors.full_messages.join(", ")
      render "verifiable_domains/new", locals: { owner: owner, profile_domains: owner_profile_domains }
    else
      redirect_to helpers.owner_domain_path_for_action(action: :verification_steps, owner: owner, domain: domain)
    end
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

    redirect_to helpers.owner_domain_path_for_action(owner: owner)
  end
end
