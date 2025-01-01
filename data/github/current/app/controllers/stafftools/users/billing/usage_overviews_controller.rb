# typed: strict
# frozen_string_literal: true

class Stafftools::Users::Billing::UsageOverviewsController < Stafftools::Users::BillingController
  before_action :ensure_vnext_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]

  sig { returns(String) }
  def self.react_bundle_name
    "billing-app"
  end

  sig { void }
  def show
    return render_404 unless GitHub.billing_enabled?

    render_react_app(
      payload: {
        customer: customer_payload(this_user),
        customer_selections: usage_customer_selections(this_user),
        period_selections: usage_period_selections,
        admin_roles: admin_roles(this_user),
        enabled_products: enabled_products,
        multi_tenant: GitHub.multi_tenant_enterprise?,
        budget_alert_details: [],
        page_data: { selected_link: :overview },
        title: "Billing Overview",
        layout: "organization_settings",
        taxDisclaimer: tax_disclaimer(this_user),
      },
    )
  end
end
