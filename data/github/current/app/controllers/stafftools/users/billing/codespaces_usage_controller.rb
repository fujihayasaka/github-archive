# typed: true
# frozen_string_literal: true

class Stafftools::Users::Billing::CodespacesUsageController < Stafftools::Users::BillingController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    render(Billing::Settings::Codespaces::UsageBodyComponent.new(
      account: this_user,
      show_spending: !this_user.delegate_billing_to_business?,
      spending_limit_path: stafftools_user_billing_spending_limits_path(this_user)
    ), layout: false)
  end
end
