# typed: true
# frozen_string_literal: true

class Stafftools::DomainsController < StafftoolsController
  before_action :verified_domains_enabled_required
  before_action :domain_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
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

  depends_on_clusters ApplicationRecord::Copilot, only: [:show], optional: true

  def show
    render "stafftools/users/domain", layout: false, locals: { domain: domain }
  end

  def update
    case update_operation
    when :verify
      verify
    when :unverify
      unverify
    when :set_token_expiration
      set_token_expiration
    else
      return render_404
    end

    redirect_to domains_index_for_domain_owner
  end

  private

  def verified_domains_enabled_required
    render_404 unless GitHub.verified_domains_enabled?
  end

  def domain_required
    render_404 unless domain.present?
  end

  memoize def domain
    VerifiableDomain.find_by(id: params[:id])
  end

  def update_operation
    params[:operation].to_s.to_sym
  end

  def verify
    domain.verify(actor: current_user, staff_action: true)

    if domain.errors.any?
      flash[:error] = domain.errors.full_messages.join(", ")
    else
      flash[:notice] = "You verified the domain #{domain.domain}."
    end
  end

  def unverify
    if domain.owner.is_a?(Business) || domain.required_for_policy_enforcement?
      domain.disable_dependent_policies(actor: current_user)
    end

    domain.unverify(actor: current_user)

    if domain.errors.any?
      flash[:error] = domain.errors.full_messages.join(", ")
    else
      flash[:notice] = "You unverified the domain #{domain.domain}."
    end
  end

  def set_token_expiration
    errors = domain.set_token_expiration_time(params[:token_expires_at], actor: current_user)
    if errors.empty?
      flash[:notice] = "Verification code expiry time for #{domain.domain} set to #{params[:token_expires_at]}"
    else
      flash[:error] = errors.to_sentence
    end
  end

  def domains_index_for_domain_owner
    if domain.owner.is_a?(User)
      stafftools_user_domains_path(domain.owner)
    else
      stafftools_enterprise_domains_path(domain.owner)
    end
  end
end
