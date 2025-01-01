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
    add_client_feature_flag([:billingplatform_copilot_premium_sku, :github_models_billing_ui], entity: this_business)
    notification = Billing::Notifications::CustomerBudgetsNotifications.new(owner: this_business, actor: current_user)
    banners = notification.budget_threshold_banners(actor: current_user)

    usage_selections_with_legacy_option = nil
    if this_business.customer.is_legacy_report_an_option?
      usage_selections_with_legacy_option = usage_report_selections.push(usage_report_legacy_selection)
      usage_selections_with_legacy_option = filter_period_selections(usage_selections_with_legacy_option, this_business.customer.billing_platform_enabled_product.migration_date)
    end

    render_react_app(
      payload: {
        customer: customer_payload(this_business),
        customer_selections: usage_customer_selections(this_business),
        period_selections: usage_period_selections,
        group_selections: usage_group_selections(this_business),
        budget_alert_details: banners.map do |banner|
          {
            text: banner.text,
            variant: banner.variant.to_s,
            dismissible: banner.dismissible?,
            dismiss_link: banner.dismissal_path,
            budget_id: banner.budget_uuid,
          }
        end,
        enabled_products: enabled_products(this_business),
        current_user_email: current_user&.default_notification_email,
        disable_usage_reports: this_business.feature_enabled?(:disable_billing_usage_reports),
        usage_report_selections: usage_selections_with_legacy_option || usage_report_selections,
        vnext_migration_date: this_business.customer.is_legacy_report_an_option? ? this_business.customer.vnext_migration_date.strftime("%B %d, %Y") : nil,
        is_multi_tenant: GitHub.multi_tenant_enterprise?,
        is_single_tenant: GitHub.single_tenant_enterprise?,
        min_custom_date: min_custom_date(customer: this_business.customer),
        copilot_premium_usage_report_enabled: this_business.feature_enabled?(:copilot_overages_usage_report) ? Copilot::Business.new(this_business).can_export_premium_usage? : false,
        billing_coding_agent_enabled: billing_coding_agent_enabled?(this_business),
        billing_spark_enabled: billing_spark_enabled?(this_business),
      },
      page_data: { selected_link: :business_billing_vnext_usage, sidebar: :billing_and_licensing },
      title: "Billing Usage",
      layout: "react_business",
    )
  end

  private

  sig { params(billing_items: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[String]) }
  def json_billing_items(billing_items)
    return [] if billing_items.nil?

    billing_items.map { |item| Billing::Platform::Api::UsageLineItem.new(item).to_json }
  end
end
