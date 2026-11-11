# typed: true
# frozen_string_literal: true

class VerifiableDomains::TokensController < ApplicationController
  include VerifiableDomainsControllerMethods

  before_action :check_verified_domains_enabled
  before_action :login_required
  before_action :ensure_if_organization_required
  before_action :find_owner!
  before_action :owner_admin_required

  def update
    domain = owner.verifiable_domains.find(params[:id])
    domain.generate_verification_token
    if domain.errors.any?
      flash[:error] = domain.errors.full_messages.join(", ")
    end

    redirect_to helpers.owner_domain_path_for_action(action: :verification_steps, owner: owner, domain: domain)
  end
end
