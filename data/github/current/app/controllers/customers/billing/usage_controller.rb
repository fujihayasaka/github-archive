# typed: strict
# frozen_string_literal: true

class Customers::Billing::UsageController < Customers::BillingController
  include Billing::UsageDependency
  T.unsafe(self).react_bundle_name = "billing-app"

  depends_on_clusters ApplicationRecord::Billing,
                      ApplicationRecord::Collab,
                      ApplicationRecord::Configurations,
                      ApplicationRecord::Copilot,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::Mysql1,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::Mysql5,
                      ApplicationRecord::NotificationsEntries,
                      ApplicationRecord::Repositories,
                      only: [:show]

  sig { void }
  def show
    notification = Billing::Notifications::CustomerBudgetsNotifications.new(owner: this_entity, actor: current_user)
    banner = notification.combined_budget_threshold_banner(actor: current_user)

    is_legacy_option = this_entity.customer&.is_legacy_report_an_option? || false
    min_custom_date = min_custom_date(customer: T.must(this_entity.customer))

    usage_selections_with_legacy_option = usage_report_selections
    if is_legacy_option
      usage_selections_with_legacy_option.push(usage_report_legacy_selection)
      usage_selections_with_legacy_option = filter_period_selections(usage_selections_with_legacy_option, this_entity.customer&.billing_platform_enabled_product&.migration_date)
    end

    migration_date = is_legacy_option ? this_entity.customer&.billing_platform_enabled_product&.migration_date&.strftime("%B %d, %Y") : nil
    report_type_selections = usage_report_type_selections(
      is_legacy_option: is_legacy_option,
      migration_date: migration_date,
      min_custom_date: min_custom_date
    )

    render_react_app(
      payload: {
        customer: customer_payload(this_entity),
        customer_selections: usage_customer_selections(this_entity),
        period_selections: usage_period_selections,
        group_selections: usage_group_selections(this_entity),
        disable_usage_reports: this_entity.feature_flag_enabled_or_raise?(:billing_platform_disable_usage_reports), # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        enabled_products: enabled_products(this_entity),
        usage_report_selections: usage_selections_with_legacy_option,
        current_user_email: current_user&.default_notification_email,
        budget_alert_details: banner&.to_payload_hash,
        min_custom_date: min_custom_date,
        report_type_selections: report_type_selections,
      },
      page_data: { selected_link: :billing_vnext_usage },
      title: "Billing Usage",
      layout: customer_billing_page_layout,
    )
  end

  private

  sig do
    params(billing_items: T.nilable(T::Array[T::Hash[T.untyped, T.untyped]]))
      .returns(T::Array[String])
  end
  def json_billing_items(billing_items)
    return [] if billing_items.nil?

    billing_items.map { |item| Billing::Platform::Api::UsageLineItem.new(item).to_json }
  end
end
