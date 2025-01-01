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
    render_react_app(
      payload: {
        customer: customer_payload(this_user),
        customer_selections: usage_customer_selections(this_user),
        period_selections: usage_period_selections,
        admin_roles: admin_roles(this_user),
        group_selections: usage_group_selections(this_user),
        budget_alert_details: [],
        layout: "organization_settings",
      },
      page_data: { selected_link: :usage },
      title: "Billing Usage",
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
