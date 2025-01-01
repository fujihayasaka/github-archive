# typed: true
# frozen_string_literal: true

class BillingSettings::SharedProductsUsageController < ApplicationController
  include OrganizationsHelper
  include GitHub::Memoizer

  before_action :login_required
  before_action :ensure_billing_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing

  def show_actions # rubocop:todo GitHub/UseRestfulActions
    render(Billing::Settings::Actions::ActionsUsageComponent.new(
      account: account,
      spending_limit_enabled: view.spending_limit_enabled?,
      spending_limit_path: view.spending_limit_path
    ), layout: false)
  end

  def show_packages # rubocop:todo GitHub/UseRestfulActions
    render(Billing::Settings::Packages::PackagesUsageComponent.new(
        account: account,
        spending_limit_enabled: view.spending_limit_enabled?,
        spending_limit_path: view.spending_limit_path
      ), layout: false)
  end

  def show_shared_storage # rubocop:todo GitHub/UseRestfulActions
    render partial: "billing_settings/github_storage_usage", locals: { view: view }
  end

  private

  memoize def account
    current_organization_for_member_or_billing || current_user
  end

  memoize def view
    BillingSettings::ProductUsageView.new(account: account, current_user: current_user)
  end
end
