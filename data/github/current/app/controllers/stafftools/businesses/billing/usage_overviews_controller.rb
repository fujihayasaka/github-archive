# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::Billing::UsageOverviewsController < Stafftools::Businesses::BillingController

  include BillingSettingsHelper

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
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
        customer: customer_payload(this_business),
        customer_selections: usage_customer_selections(this_business),
        period_selections: usage_period_selections,
        admin_roles: admin_roles(this_business),
        enabled_products: enabled_products,
        multi_tenant: GitHub.multi_tenant_enterprise?,
        budget_alert_details: [],
        page_data: { selected_link: :business_billing_vnext_overview, sidebar: :billing_and_licensing },
        title: "Billing Overview",
        layout: "react_business",
        taxDisclaimer: tax_disclaimer(this_business),
        showVolumeLicenseSpendTile: this_business.show_volume_license_spend_tile_for_business?,
        volumeLicenseSpendTileData: volume_license_spend(this_business),
        isCopilotStandalone: this_business.copilot_licensing_enabled?,
      },
    )
  end
end
