# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::UsagesController < Stafftools::Businesses::BillingController
  extend T::Sig

  include ReactHelper

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

      format.html do
        use_usage_chart_data_endpoint = this_business&.feature_enabled?(:usage_chart_api)
        render_react_app(
          payload: {
            customer: customer_payload(this_business),
            customer_selections: usage_customer_selections(this_business),
            period_selections: usage_period_selections,
            group_selections: usage_group_selections(use_usage_chart_data_endpoint),
            budget_alert_details: [],
            usage_report_selections: usage_report_selections,
            billing_platform_enabled_products: this_business.customer.products_billed_via_billing_platform_friendly_names,
            current_user_email: current_user&.default_notification_email,
            show_billing_vnext_beta_usage_banner: this_business.feature_enabled?(:billing_vnext_beta_usage_banner),
            use_usage_chart_data_endpoint: use_usage_chart_data_endpoint,
            use_usage_table_data_endpoint: this_business&.feature_enabled?(:billing_usage_table_api),

          },
          page_data: { selected_link: :business_billing_settings },
          title: "Usage (Beta)",
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
