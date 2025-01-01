# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::UsagesController < Stafftools::Businesses::BillingController

  include Billing::UsageDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  sig { returns(String) }
  def self.react_bundle_name
    "billing-app"
  end

  def show
    is_legacy_report_an_option = this_business.customer.is_legacy_report_an_option?

    usage_selections_with_legacy_option = if is_legacy_report_an_option
      usage_selections_with_legacy_option = usage_report_selections.push(usage_report_legacy_selection)
      usage_selections_with_legacy_option = filter_period_selections(usage_selections_with_legacy_option, this_business.customer.billing_platform_enabled_product.migration_date)
    end

    render_react_app(
      payload: {
        customer: customer_payload(this_business),
        customer_selections: usage_customer_selections(this_business),
        period_selections: usage_period_selections,
        group_selections: usage_group_selections(this_business),
        budget_alert_details: [],
        usage_report_selections: usage_selections_with_legacy_option || usage_report_selections,
        billing_platform_enabled_products: this_business.customer.products_billed_via_billing_platform_friendly_names,
        current_user_email: current_user&.default_notification_email,
        vnext_migration_date: is_legacy_report_an_option ? this_business.customer.vnext_migration_date.strftime("%b %d, %Y") : nil,
        min_custom_date: min_custom_date(customer: this_business.customer)
      },
      page_data: { selected_link: :business_billing_settings },
      title: "Usage",
    )
  end

  private

  def json_billing_items(billing_items)
    return [] if billing_items.nil?

    billing_items.map { |item| Billing::Platform::Api::UsageLineItem.new(item).to_json }
  end
end
