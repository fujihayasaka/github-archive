# typed: strict
# frozen_string_literal: true

class Businesses::Billing::UsagesController < Businesses::BillingsController

  include Billing::Platform::Api::Utils
  include Billing::UsageDependency

  T.unsafe(self).react_bundle_name = "billing-app"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:show]

  sig { void }
  def show
    add_client_feature_flag([:billing_ui_top_cost_centers_usage_table], entity: this_business)
    notification = Billing::Notifications::CustomerBudgetsNotifications.new(owner: this_business, actor: current_user)
    banner = notification.combined_budget_threshold_banner(actor: current_user)

    is_legacy_option = this_business.customer.is_legacy_report_an_option?
    min_custom_date = min_custom_date(customer: this_business.customer)

    usage_selections_with_legacy_option = nil
    if is_legacy_option
      usage_selections_with_legacy_option = usage_report_selections.push(usage_report_legacy_selection)
      usage_selections_with_legacy_option = filter_period_selections(usage_selections_with_legacy_option, this_business.customer.billing_platform_enabled_product.migration_date)
    end

    migration_date = is_legacy_option ? this_business.customer.vnext_migration_date.strftime("%B %d, %Y") : nil
    report_type_selections = usage_report_type_selections(
      is_legacy_option: is_legacy_option,
      migration_date: migration_date,
      min_custom_date: min_custom_date
    )

    render_react_app(
      payload: {
        customer: customer_payload(this_business),
        customer_selections: usage_customer_selections(this_business),
        period_selections: usage_period_selections,
        group_selections: usage_group_selections(this_business),
        budget_alert_details: banner&.to_payload_hash,
        enabled_products: enabled_products(this_business),
        current_user_email: current_user&.default_notification_email,
        disable_usage_reports: FeatureFlag.vexi.enabled?(:disable_billing_usage_reports, this_business, default: false),
        usage_report_selections: usage_selections_with_legacy_option || usage_report_selections,
        is_multi_tenant: GitHub.multi_tenant_enterprise?,
        is_single_tenant: GitHub.single_tenant_enterprise?,
        min_custom_date: min_custom_date,
        report_type_selections: report_type_selections,
        is_copilot_standalone: this_business.is_copilot_standalone?,
      },
      page_data: { selected_link: :business_billing_vnext_usage, sidebar: :billing_and_licensing },
      title: "Billing Usage",
      layout: "react_business"
    )
  end

  private

  sig { params(billing_items: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[String]) }
  def json_billing_items(billing_items)
    return [] if billing_items.nil?

    billing_items.map { |item| Billing::Platform::Api::UsageLineItem.new(item).to_json }
  end
end
