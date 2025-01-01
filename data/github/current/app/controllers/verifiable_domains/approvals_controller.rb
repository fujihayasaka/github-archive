# typed: true
# frozen_string_literal: true

class VerifiableDomains::ApprovalsController < ApplicationController
  include VerifiableDomainsControllerMethods

  before_action :check_verified_domains_enabled
  before_action :login_required
  before_action :ensure_if_organization_required
  before_action :find_owner!
  before_action :owner_admin_required

  def update
    domain = owner.verifiable_domains.find(params[:id])

    if !domain.approve(actor: current_user)
      flash[:error] = domain.errors.full_messages.join(", ")
    else
      flash[:notice] = "You approved the domain #{domain.domain}."
    end
    redirect_to helpers.owner_domain_path_for_action(owner: owner)
  end
end
