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
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_business, **usage_filter_params)
        if !this_business.billing_manager?(current_user) && !this_business.owner?(current_user)
          new_query = {
            usage_entity_id: query[:usage_entity_id].to_s,
            billing_period: query[:billing_period],
            year: query[:year],
            month: query[:month],
            day: query[:day],
            hour: query[:hour],
            group_by: 5,
          }

          usage_response = Billing::Platform::Api::Client.new.get_usage_line_items(**new_query)
          if usage_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occurred" }, status: 500
          end

          usage = filter_usage_by_query(usages: usage_response[:billingItems], query: query)
        else
          usage_response = Billing::Platform::Api::Client.new.get_usage_line_items(**T.unsafe(query))
          if usage_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occurred" }, status: 500
          end
          usage = usage_response[:billingItems]
        end

        usages = filter_repo_usage_by_ownership(usages: usage, current_user: current_user, entity: this_business)
        render json: { usage: json_billing_items(usages) }, status: 200
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        render json: { error: "Unable to query usage", usage: [] }, status: 500
      end
      format.html do
        notification = Billing::Notifications::CustomerBudgetsNotifications.new(owner: this_business, actor: current_user)
        banners = notification.budget_threshold_banners(actor: T.must(current_user))

        custom_date_range_enabled = this_business.feature_enabled?(:billing_custom_date_range_usage_report)

        usage_selections_with_legacy_option = nil
        if this_business.customer.is_legacy_report_an_option?
          usage_selections_with_legacy_option = usage_report_selections(custom_date_range_enabled).push(usage_report_legacy_selection)
          usage_selections_with_legacy_option = filter_period_selections(usage_selections_with_legacy_option, this_business.customer.billing_platform_enabled_product.migration_date)
        end

        render_react_app(
          payload: {
            customer: customer_payload(this_business),
            customer_selections: usage_customer_selections(this_business),
            period_selections: usage_period_selections,
            group_selections: usage_group_selections,
            budget_alert_details: banners.map do |banner|
              {
                text: banner.text,
                variant: banner.variant.to_s,
                dismissible: banner.dismissible?,
                dismiss_link: banner.dismissal_path,
                budget_id: banner.budget_uuid,
              }
            end,
            billing_platform_enabled_products: this_business.customer.products_billed_via_billing_platform_friendly_names,
            current_user_email: current_user&.default_notification_email,
            disable_usage_reports: this_business.feature_enabled?(:disable_billing_usage_reports),
            usage_report_selections: usage_selections_with_legacy_option || usage_report_selections(custom_date_range_enabled),
            vnext_migration_date: this_business.customer.is_legacy_report_an_option? ? this_business.customer.vnext_migration_date.strftime("%B %d, %Y") : nil,
            show_billing_vnext_beta_usage_banner: this_business.feature_enabled?(:billing_vnext_beta_usage_banner),
            is_multi_tenant: GitHub.multi_tenant_enterprise?,
            is_single_tenant: GitHub.single_tenant_enterprise?,
            show_custom_date_range_usage_report: custom_date_range_enabled,
            min_custom_date: min_custom_date(customer: this_business.customer),
          },
          page_data: { selected_link: :business_billing_vnext_usage },
          title: "Billing Usage",
          layout: "react_business",
          ssr: true,
        )
      end
    end
  end

  private

  sig { params(billing_items: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[String]) }
  def json_billing_items(billing_items)
    return [] if billing_items.nil?

    billing_items.map { |item| Billing::Platform::Api::UsageLineItem.new(item).to_json }
  end
end
