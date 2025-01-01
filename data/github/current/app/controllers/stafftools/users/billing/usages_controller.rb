# typed: strict
# frozen_string_literal: true

class Stafftools::Users::Billing::UsagesController < Stafftools::Users::BillingController
  T.unsafe(self).react_bundle_name = "billing-app"

  before_action :ensure_vnext_enabled

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
                      ApplicationRecord::Ballast,
                      only: [:show]

  sig { void }
  def show
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_user, **usage_filter_params)
        this_entity = self.this_user

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

        render json: { usage: json_billing_items(usage) }, status: 200
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        render json: { error: "Unable to query usage", usage: [] }, status: 500
      end
      format.html do
        render_react_app(
          payload: {
            customer: customer_payload(this_user),
            customer_selections: usage_customer_selections(this_user),
            period_selections: usage_period_selections,
            admin_roles: admin_roles(this_user),
            group_selections: usage_group_selections,
            budget_alert_details: [],
            layout: "organization_settings",
          },
          page_data: { selected_link: :usage },
          title: "Billing Usage",
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
