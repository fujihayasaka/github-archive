# typed: true
# frozen_string_literal: true

class Stafftools::DomainsController < StafftoolsController

  before_action :check_verified_domains_enabled
  before_action :load_domain

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    render "stafftools/users/domain", layout: false, locals: { domain: @domain }
  end

  def verify # rubocop:todo GitHub/UseRestfulActions
    @domain.verify(actor: current_user, staff_action: true)

    if @domain.errors.any?
      flash[:error] = @domain.errors.full_messages.join(", ")
    else
      flash[:notice] = "You verified the domain #{@domain.domain}."
    end

    redirect_to domains_index_for_domain_owner
  end

  def unverify # rubocop:todo GitHub/UseRestfulActions
    if @domain.owner.is_a?(Business) || @domain.required_for_policy_enforcement?
      @domain.disable_dependent_policies(actor: current_user)
    end

    @domain.unverify(actor: current_user)

    if @domain.errors.any?
      flash[:error] = @domain.errors.full_messages.join(", ")
    else
      flash[:notice] = "You unverified the domain #{@domain.domain}."
    end

    redirect_to domains_index_for_domain_owner
  end

  def set_token_expiration # rubocop:todo GitHub/UseRestfulActions
    errors = @domain.set_token_expiration_time(params[:token_expires_at], actor: current_user)
    if errors.empty?
      flash[:notice] = "Verification code expiry time for #{@domain.domain} set to #{params[:token_expires_at]}"
    else
      flash[:error] = errors.to_sentence
    end
    redirect_to domains_index_for_domain_owner
  end

  private

  def domains_index_for_domain_owner
    if @domain.owner.is_a?(User)
      stafftools_user_domains_path(@domain.owner)
    else
      stafftools_enterprise_domains_path(@domain.owner)
    end
  end

  def load_domain
    @domain = VerifiableDomain.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # Before action that will 404 if verified domains aren't enabled.
  def check_verified_domains_enabled
    render_404 unless GitHub.verified_domains_enabled?
  end
end
