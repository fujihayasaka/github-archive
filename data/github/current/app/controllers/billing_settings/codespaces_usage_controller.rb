# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/ControllersShouldHaveTests
class BillingSettings::CodespacesUsageController < ApplicationController
  # rubocop:enable GitHub/ControllersShouldHaveTests
  include OrganizationsHelper

  before_action :ensure_billing_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:show]

  def show
    account = current_organization_for_member_or_billing || current_user
    view = BillingSettings::ProductUsageView.new(account: account, current_user: current_user)

    render(Billing::Settings::Codespaces::UsageBodyComponent.new(
      account: account,
      show_spending: view.spending_limit_enabled?,
      spending_limit_path: view.spending_limit_path
    ), layout: false)
  end
end
