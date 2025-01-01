# typed: true
# frozen_string_literal: true

class Businesses::BillingSettings::MeteredUsageController < Businesses::BusinessController
  include GitHub::Memoizer

  before_action :ensure_billing_enabled
  before_action :business_access_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:show]

  PRODUCTS_FOR_TOTAL_SPEND = %w[
    actions
    packages
    shared_storage
    codespaces
    copilot
  ]

  def show
    view = Businesses::BillingSettings::ShowView.new(current_user: current_user, business: this_business)

    render(Billing::Settings::MeteredUsageComponent.new(
      manage_spending_limit_href: view.manage_spending_limit_href,
      has_error: usage_checker.request_error?,
      metered_service_total_cents: metered_service_total_cents,
      standalone_enterprise_enabled: view.copilot_standalone?
    ), layout: false)
  end

  private

  memoize def metered_service_total_cents
    usages = PRODUCTS_FOR_TOTAL_SPEND.reduce([]) do |memo, product|
      memo.concat usage_checker.usage_results_for(product:)
    end

    usage_checker.total_paid_usage_for(usages:)
  end

  memoize def usage_checker
    ::Billing::UsageChecker.new(
      account: this_business,
      product_names: PRODUCTS_FOR_TOTAL_SPEND
    )
  end
end
