# typed: true
# frozen_string_literal: true

# Controller getting total metered usage for organizations
class Orgs::BillingSettings::MeteredUsageController < Orgs::Controller
  include GitHub::Memoizer

  before_action :login_required
  before_action :block_if_meuse_deprecated
  before_action :org_billing_management_only
  before_action :ensure_billing_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
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
    org = current_organization_for_member_or_billing

    render(Billing::Settings::MeteredUsageComponent.new(
      manage_spending_limit_href: settings_org_billing_tab_path(organization_id: org.display_login, tab: "spending_limit"),
      has_error: usage_checker.request_error?,
      metered_service_total_cents: metered_service_total_cents
    ), layout: false)
  end

  private

  def block_if_meuse_deprecated
    if FeatureFlag.vexi.enabled?(:billing_deprecate_meuse_components_part_two, current_user, default: false)
      render_404
    end
  end

  def ensure_billing_enabled
    render_404 unless GitHub.billing_enabled?
  end

  memoize def metered_service_total_cents
    usages = PRODUCTS_FOR_TOTAL_SPEND.reduce([]) do |memo, product|
      memo.concat usage_checker.usage_results_for(product:)
    end

    usage_checker.total_paid_usage_for(usages:)
  end

  memoize def usage_checker
    ::Billing::UsageChecker.new(
      account: current_organization_for_member_or_billing,
      product_names: PRODUCTS_FOR_TOTAL_SPEND
    )
  end
end
