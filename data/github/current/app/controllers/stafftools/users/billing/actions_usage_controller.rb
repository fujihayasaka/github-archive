# typed: true
# frozen_string_literal: true

class Stafftools::Users::Billing::ActionsUsageController < Stafftools::Users::BillingController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    billable_owner = this_user.billable_owner

    render(Billing::Settings::Actions::ActionsUsageComponent.new(
    account: this_user,
    spending_limit_enabled: ::Billing::Budget.configurable?(billable_owner),
    spending_limit_path:  stafftools_user_billing_spending_limits_path(this_user)), layout: false)
  end
end
