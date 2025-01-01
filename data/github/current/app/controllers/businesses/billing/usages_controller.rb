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
        disable_usage_reports: this_business.feature_flag_enabled_or_raise?(:disable_billing_usage_reports), # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        usage_report_selections: usage_selections_with_legacy_option || usage_report_selections,
        vnext_migration_date: is_legacy_option ? this_business.customer.vnext_migration_date.strftime("%B %d, %Y") : nil,
        is_multi_tenant: GitHub.multi_tenant_enterprise?,
        is_single_tenant: GitHub.single_tenant_enterprise?,
        min_custom_date: min_custom_date,
        copilot_premium_usage_report_enabled: copilot_premium_usage_report_enabled?,
        report_type_selections: report_type_selections,
        billing_coding_agent_enabled: billing_coding_agent_enabled?(this_business),
        billing_spark_enabled: billing_spark_enabled?(this_business),
        slug: this_business.slug,
        can_request_all_usage: this_business.owner?(current_user) || this_business.billing_manager?(current_user),
        is_copilot_standalone: this_business.is_copilot_standalone?,
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

  sig { returns(T::Boolean) }
  def copilot_premium_usage_report_enabled?
    if this_business.feature_flag_enabled_or_raise?(:copilot_overages_usage_report) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      Copilot::Business.new(this_business).can_export_premium_usage? && show_pru_option_on_usage_page?
    else
      false
    end
  end

  sig { returns(T::Boolean) }
  def show_pru_option_on_usage_page?
    !FeatureFlag.vexi.enabled?(:pru_billing_page, this_business, default: false)
  end
end
