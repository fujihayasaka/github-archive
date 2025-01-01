# typed: true
# frozen_string_literal: true

class Biztools::UsersController < BiztoolsController
  before_action :ensure_user_exists, only: [:show, :enable_tos_prompt]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def index
    render "biztools/users/index"
  end

  def show
    counts = {
      total_repos: current_account.repositories.size,
      public_repos: current_account.public_repositories.size,
      owned_apps: current_account.oauth_applications.size,
    }

    if current_account.user?
      marketplace_agreement_signatures = Marketplace::AgreementSignature.for_user(current_account).
        includes(:agreement, :organization)

      orgs = {
        member_orgs: current_account.organizations.size,
        owned_orgs: current_account.owned_organizations.size,
        billing_orgs: current_account.billing_manager_organizations.size,
      }
      counts.merge! orgs
      counts[:orgs] = orgs.values.sum

      oauths = {
        owned_apps: counts[:owned_apps],
        authed_apps: current_account.oauth_authorizations.third_party.size,
        tokens: current_account.oauth_accesses.personal_tokens.size,
      }
      counts.merge! oauths
      counts[:oauths] = oauths.values.sum

      collabs = {
        contributed_repos: current_account.ranked_contributed_repositories.size,
      }
      counts.merge! collabs
      counts[:collabs] = collabs.values.sum
      counts[:managed_marketplace_listings] = Marketplace::Listing.
        editable_by(current_account).count
      counts[:marketplace_agreement_signatures] = marketplace_agreement_signatures.count
    else
      marketplace_agreement_signatures = Marketplace::AgreementSignature.for_org(current_account).
        includes(:agreement, :signatory)

      counts[:webhooks] = current_account.hooks.size if GitHub.hookshot_enabled?
      counts[:teams] = current_account.teams.size
      counts[:members] = current_account.members.size
      counts[:admins] = current_account.admins.size
      counts[:owned_marketplace_listings] = Marketplace::Listing.
        for_org(current_account).count
      if GitHub.billing_enabled?
        counts[:billing_managers] = current_account.billing_managers.size
      end
      counts[:marketplace_agreement_signatures] = marketplace_agreement_signatures.count
    end

    case current_account.site_admin_context
    when "organization"
      render "biztools/organizations/show", locals: {
        last_transaction: current_account.billing_transactions.sales.last,
        counts: counts,
        marketplace_agreement_signatures: marketplace_agreement_signatures.latest,
      }
    when "user"
      render "biztools/users/show", locals: {
        last_transaction: current_account.billing_transactions.sales.last,
        counts: counts,
        marketplace_agreement_signatures: marketplace_agreement_signatures.latest,
      }
    end
  end

  def enable_tos_prompt # rubocop:todo GitHub/UseRestfulActions
    current_account.terms_of_service.enable_corporate_upgrade_prompt
    flash[:notice] = "Enabled Corporate Terms of Service prompt"
    redirect_to "/biztools/users/#{current_account}"
  end
end
