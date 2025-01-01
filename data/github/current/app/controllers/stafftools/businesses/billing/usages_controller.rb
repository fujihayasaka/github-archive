# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::UsagesController < Stafftools::Businesses::BillingController

  include ReactHelper
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
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_business, **usage_filter_params)

        begin
          usage = Billing::Platform::Api::Client.new.get_usage_line_items(
            usage_entity_id: query[:usage_entity_id],
            product: query[:product].to_s,
            sku: query[:sku].to_s,
            billing_period: query[:billing_period],
            year: query[:year],
            month: query[:month],
            day: query[:day],
            hour: query[:hour],
            org_id: query[:org_id],
            repo_id: query[:repo_id],
            group_by: query[:group_by],
          )
        rescue => e # rubocop:todo Lint/GenericRescue
          Failbot.report(e)
          return render json: { error: "Unable to query usage", usage: [] }, status: 500
        end

        if usage.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "An unknown error occured", usage: [] }, status: 500
        end

        render json: { usage: json_billing_items(usage[:billingItems]) }, status: 200
      end

      custom_date_range_enabled = this_business.feature_enabled?(:billing_custom_date_range_usage_report)

      is_legacy_report_an_option = this_business.customer.is_legacy_report_an_option?

      usage_selections_with_legacy_option = if is_legacy_report_an_option
        usage_selections_with_legacy_option = usage_report_selections(custom_date_range_enabled).push(usage_report_legacy_selection)
        usage_selections_with_legacy_option = filter_period_selections(usage_selections_with_legacy_option, this_business.customer.billing_platform_enabled_product.migration_date)
      end

      format.html do
        render_react_app(
          payload: {
            customer: customer_payload(this_business),
            customer_selections: usage_customer_selections(this_business),
            period_selections: usage_period_selections,
            group_selections: usage_group_selections,
            budget_alert_details: [],
            usage_report_selections: usage_selections_with_legacy_option || usage_report_selections(custom_date_range_enabled),
            billing_platform_enabled_products: this_business.customer.products_billed_via_billing_platform_friendly_names,
            current_user_email: current_user&.default_notification_email,
            vnext_migration_date: is_legacy_report_an_option ? this_business.customer.vnext_migration_date.strftime("%b %d, %Y") : nil,
            show_billing_vnext_beta_usage_banner: this_business.feature_enabled?(:billing_vnext_beta_usage_banner),
            show_custom_date_range_usage_report: custom_date_range_enabled,
            min_custom_date: min_custom_date(customer: this_business.customer)
          },
          page_data: { selected_link: :business_billing_settings },
          title: "Usage",
          ssr: true
        )
      end
    end
  end

  private

  def json_billing_items(billing_items)
    return [] if billing_items.nil?

    billing_items.map { |item| Billing::Platform::Api::UsageLineItem.new(item).to_json }
  end
end
