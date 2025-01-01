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

    add_client_feature_flag([:pru_billing_page, :billing_enable_coding_agent_product], entity: this_business)
    react_payload = {
      customer: customer_payload(this_business),
      customer_selections: usage_customer_selections(this_business),
      period_selections: usage_period_selections,
      admin_roles: admin_roles(this_business),
      enabled_products: enabled_products(this_business),
      multi_tenant: GitHub.multi_tenant_enterprise?,
      budget_alert_details: nil,
      page_data: { selected_link: :business_billing_vnext_overview, sidebar: :billing_and_licensing },
      title: "Billing Overview",
      layout: "react_business",
      taxDisclaimer: tax_disclaimer(this_business),
      showVolumeLicenseSpendTile: this_business.show_volume_license_spend_tile_for_business?,
      volumeLicenseSpendTileData: volume_license_spend(this_business),
      isCopilotStandalone: this_business.copilot_licensing_enabled?,
      copilot_premium_usage_report_enabled: this_business.feature_flag_enabled_or_raise?(:copilot_overages_usage_report) ? Copilot::Business.new(this_business).can_export_premium_usage? : false, # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      showPrepaidCredits: this_business.invoiced? && has_past_prepaid_credits?,
      billing_coding_agent_enabled: billing_coding_agent_enabled?(this_business),
      billing_spark_enabled: billing_spark_enabled?(this_business),
    }

    if react_payload[:showPrepaidCredits]
      react_payload[:prepaidCreditsTileData] = { prepaidCreditsBalance: prepaid_credit_balance }
    end

    invoice = fetch_latest_unpaid_invoice
    show_invoice = invoice && this_business.show_past_invoices_tab?(current_user, is_stafftools_action: true)

    react_payload[:showLatestInvoiceTile] = show_invoice

    if show_invoice
      react_payload[:latestInvoiceTileData] = {
        latestInvoiceBalance: invoice.balance,
        invoiceDueDate: DateTime.parse(invoice.due_date).strftime("%B %-d, %Y"),
        invoiceNumber: invoice.invoice_number,
        overdue: invoice.past_due?,
        meteredViaAzure: this_business.metered_via_azure?,
        businessName: this_business.name,
      }
    end

    render_react_app(payload: react_payload)
  end

  private

  sig { returns(T::Boolean) }
  def has_past_prepaid_credits?
    Billing::PrepaidMeteredUsageRefill.where(owner: this_business).exists?
  end

  sig { returns(Float) }
  memoize def prepaid_credit_balance
    this_business.customer&.credit_balance.to_f
  end


  sig { returns(T.nilable(::Billing::Zuora::Invoice)) }
  memoize def fetch_latest_unpaid_invoice
    return @latest_unpaid_invoice if defined?(@latest_unpaid_invoice)

    invoices = T.let(
      Billing::Zuora::Invoice.invoices_for_account(this_business.customer&.zuora_account_id.to_s)
      .reject(&:paid?)
      .sort_by(&:invoice_date)
      .reverse, T.nilable(T::Array[::Billing::Zuora::Invoice])
    )

    @latest_unpaid_invoice = T.let(invoices&.first, T.nilable(::Billing::Zuora::Invoice))
  rescue Zuorest::HttpError, Faraday::Error => e
    Failbot.report!(e, app: "github-zuora")
    @latest_unpaid_invoice = T.let(nil, T.nilable(::Billing::Zuora::Invoice))
  end
end
