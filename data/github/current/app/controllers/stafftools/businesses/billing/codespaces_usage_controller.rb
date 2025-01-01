# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::CodespacesUsageController < Stafftools::Businesses::BillingController
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
    only: [:show], optional: true

  def show
    render(Billing::Settings::Codespaces::UsageBodyComponent.new(
      account: this_business,
      show_spending: true,
    ), layout: false)
  end
end
