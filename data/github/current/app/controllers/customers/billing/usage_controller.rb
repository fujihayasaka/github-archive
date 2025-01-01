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
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_entity, **usage_filter_params)
        this_entity = self.this_entity
        if this_entity.is_a?(Business) && !this_entity.billing_manager?(current_user) && !this_entity.owner?(current_user)
          new_query = {
            usage_entity_id: query[:usage_entity_id],
            product: query[:product],
            sku: query[:sku],
            billing_period: query[:billing_period],
            year: query[:year],
            month: query[:month],
            day: query[:day],
            hour: query[:hour],
            org_id: query[:org_id],
            repo_id: query[:repo_id],
            group_by: BillingPlatform::Base::UsageGroupBy::GroupByOrgRepoProductSku,
          }

          usage_response = Billing::Platform::Api::Client.new.get_usage_line_items(**new_query)
          if usage_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occurred" }, status: 500
          end

          usage = filter_usage_by_query(usages: usage_response[:billingItems], query: query)
        else
          new_query = {
            usage_entity_id: query[:usage_entity_id],
            product: query[:product],
            sku: query[:sku],
            billing_period: query[:billing_period],
            year: query[:year],
            month: query[:month],
            day: query[:day],
            hour: query[:hour],
            org_id: query[:org_id],
            repo_id: query[:repo_id],
            group_by: query[:group_by],
          }
          usage_response = Billing::Platform::Api::Client.new.get_usage_line_items(**new_query)
          if usage_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occurred" }, status: 500
          end
          usage = usage_response[:billingItems]
        end

        usage = filter_repo_usage_by_ownership(usages: usage, current_user: current_user, entity: this_entity)

        render json: { usage: json_billing_items(usage) }, status: 200
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        render json: { error: "Unable to query usage", usage: [] }, status: 500
      end
      format.html do
        notification = Billing::Notifications::CustomerBudgetsNotifications.new(owner: this_entity, actor: current_user)
        banners = notification.budget_threshold_banners(actor: T.must(current_user))
        custom_date_range_enabled = this_entity.feature_enabled?(:billing_custom_date_range_usage_report)

        render_react_app(
          payload: {
            customer: customer_payload(this_entity),
            customer_selections: usage_customer_selections(this_entity),
            period_selections: usage_period_selections,
            group_selections: usage_group_selections,
            disable_usage_reports: this_entity.feature_enabled?(:billing_platform_disable_usage_reports),
            billing_platform_enabled_products: enabled_products.map { |product| product[:friendlyProductName] },
            usage_report_selections: usage_report_selections(custom_date_range_enabled),
            current_user_email: current_user&.default_notification_email,
            budget_alert_details: banners.map do |banner|
              {
                text: banner.text,
                variant: banner.variant.to_s,
                dismissible: banner.dismissible?,
                dismiss_link: banner.dismissal_path,
                budget_id: banner.budget_uuid,
              }
            end,
            show_custom_date_range_usage_report: custom_date_range_enabled,
            min_custom_date: min_custom_date(customer: T.must(this_entity.customer))
          },
          page_data: { selected_link: :billing_vnext_usage },
          title: "Billing Usage",
          layout: customer_billing_page_layout,
          ssr: true,
        )
      end
    end
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
