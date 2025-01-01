# typed: true
# frozen_string_literal: true

class VerifiableDomains::VerificationsController < ApplicationController
  include VerifiableDomainsControllerMethods

  before_action :check_verified_domains_enabled
  before_action :login_required
  before_action :ensure_if_organization_required
  before_action :find_owner!
  before_action :owner_admin_required

  javascript_bundle "verified-domains"
  stylesheet_bundle :settings

  depends_on_clusters \
    ApplicationRecord::Mysql1,
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
    only: [:show]

  def show
    domain = owner.verifiable_domains.find(params[:id])

    if domain.verified? # can't re-verify a domain
      redirect_to helpers.owner_domain_path_for_action(owner: owner)
    else
      render "verifiable_domains/verification_steps", locals: { domain: domain }
    end
  end

  def update
    domain = owner.verifiable_domains.find(params[:id])
    domain.verify(actor: current_user, request_timeout: GitHub.request_timeout(request.env))

    if domain.errors.any?
      flash[:error] = domain.errors.full_messages.join(", ")
      redirect_to helpers.owner_domain_path_for_action(action: :verification_steps, owner: owner, domain: domain)
    else
      flash[:notice] = "You verified the domain #{domain.domain}."
      redirect_to helpers.owner_domain_path_for_action(owner: owner)
    end
  end
end
