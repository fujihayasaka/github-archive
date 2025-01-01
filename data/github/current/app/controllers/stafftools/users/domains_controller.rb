# typed: true
# frozen_string_literal: true

class Stafftools::Users::DomainsController < StafftoolsController
  before_action :ensure_org_not_user
  before_action :ensure_user_exists

  layout "layouts/stafftools/organization/overview"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    profile_domains = [
      this_user.profile_blog,
      this_user.profile_email,
    ].reject(&:blank?).map { |domain| VerifiableDomain.normalize_domain(domain.to_s) }.uniq
    verifiable_domains = VerifiableDomain.
      usable_for(this_user).
      paginate(page: params[:page], per_page: 10)

    render(
      "stafftools/users/domains/index",
      locals: {
        organization: this_user,
        profile_domains: profile_domains,
        verifiable_domains: verifiable_domains
      },
    )
  end
end
