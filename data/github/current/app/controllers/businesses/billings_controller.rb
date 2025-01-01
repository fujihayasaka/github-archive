# typed: strict
# frozen_string_literal: true

class Businesses::BillingsController < Businesses::BusinessController
  include GitHub::Memoizer
  include BillingSettingsHelper
  include Billing::BillingChecksDependency
  include Billing::ProductsDependency
  include Billing::TrustTierDependency

  T.unsafe(self).react_bundle_name = "billing-app"

  stylesheet_bundle :billing

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

  before_action :require_business_access
  before_action :ensure_billing_enabled
  before_action do
    T.bind(self, Businesses::BillingsController)
    ensure_vnext_enabled(entity: this_business)
  end
  before_action :ensure_customer

  sig { void }
  def show
    add_client_feature_flag([:pru_billing_page, :billing_enable_coding_agent_product], entity: this_business)

    begin
      notification = Billing::Notifications::CustomerBudgetsNotifications.new(owner: this_business, actor: current_user)
      banner = notification.combined_budget_threshold_banner(actor: current_user)
    rescue => e # rubocop:todo Lint/RescueException
      Failbot.report(e)
      GitHub.dogstats.increment("billing_platform.budget_banner_error")
      banner = nil
    end

    react_page_payload = {
      customer: customer_payload(this_business),
      customer_selections: usage_customer_selections(this_business),
      period_selections: usage_period_selections,
      admin_roles: admin_roles(this_business),
      enabled_products: enabled_products(this_business),
      multi_tenant: GitHub.multi_tenant_enterprise?,
      budget_alert_details: banner&.to_payload_hash,
      showTrustTierBanner: show_trust_tier_banner?(this_business),
      showVolumeLicenseSpendTile: this_business.show_volume_license_spend_tile?(current_user),
      showPaymentDueTile: this_business.show_payment_due_tile?(current_user),
      showLatestInvoiceTile: this_business.show_past_invoices_tab?(current_user) && invoice.present?,
      show_new_usage_chart: this_business.feature_flag_enabled_or_raise?(:billing_platform_accessibility_usage_chart), # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      taxDisclaimer: tax_disclaimer(this_business),
      showPrepaidCredits: has_past_prepaid_credits?,
      isCopilotStandalone: this_business.copilot_licensing_enabled?,
      copilot_premium_usage_report_enabled: this_business.feature_flag_enabled_or_raise?(:copilot_overages_usage_report) ? Copilot::Business.new(this_business).can_export_premium_usage? : false, # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      copilotIapSubscription: false, # Businesses can't have IAP subcriptions currently
      billing_coding_agent_enabled: billing_coding_agent_enabled?(this_business),
      billing_spark_enabled: billing_spark_enabled?(this_business),
      billingAddCostCenterDescription: FeatureFlag.vexi.enabled?(:billing_add_cost_center_description, this_business, default: false)
    }

    if react_page_payload[:showVolumeLicenseSpendTile]
      react_page_payload[:volumeLicenseSpendTileData] = volume_license_spend(this_business)
    end

    if react_page_payload[:showPaymentDueTile]
      react_page_payload[:paymentDueTileData] = {
        latestBillAmount: latest_bill_amount,
        nextPaymentDate: next_billing_date_or_latest_bill,
        autoPay: this_business.customer.has_auto_pay_enabled?,
        hasBill: this_business.has_bill?,
        overdue: this_business.bill_overdue?,
        meteredViaAzure: this_business.metered_via_azure?
      }
    end

    if react_page_payload[:showLatestInvoiceTile]
      react_page_payload[:latestInvoiceTileData] = {
        latestInvoiceBalance: invoice&.balance,
        invoiceDueDate: DateTime.parse(invoice&.due_date).strftime("%B %d, %Y"),
        invoiceNumber: invoice&.invoice_number,
        overdue: invoice&.past_due?,
        meteredViaAzure: this_business.metered_via_azure?,
      }
    end

    if react_page_payload[:showPrepaidCredits]
      react_page_payload[:prepaidCreditsTileData] = { prepaidCreditsBalance: prepaid_credit_balance }
    end

    should_show_overdue_banner = this_business.feature_flag_enabled_or_raise?(:ghe_sales_serve_overdue) && this_business.past_due_invoice? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    render_react_app(
      payload: react_page_payload,
      page_data: { selected_link: :business_billing_vnext_overview, sidebar: :billing_and_licensing },
      title: "Billing Overview",
      layout_locals_generator: -> {
        {
          banner_component:
            if should_show_overdue_banner
              view_context.render(
                Billing::Settings::EnterpriseWithOutstandingInvoicesPleasePayComponent.new(business: this_business, current_user: current_user),
              )
            else
              view_context.render(
                Billing::Settings::EnterpriseContractEarlyExpirationBannerComponent.new(business: this_business, current_user: current_user),
              )
            end,
        }
      },
      layout: "react_business",
    )
  end

  private

  sig { returns(T.nilable(::Billing::Zuora::Invoice)) }
  def invoice
    return @_invoice if defined?(@_invoice)

    invoices ||= T.let(Billing::Zuora::Invoice.invoices_for_account(this_business.customer&.zuora_account_id.to_s)
      .reject(&:paid?)
      .sort_by(&:invoice_date)
      .reverse, T.nilable(T::Array[::Billing::Zuora::Invoice]))

    @_invoice = T.let(invoices&.first, T.nilable(::Billing::Zuora::Invoice))
  rescue Zuorest::HttpError, Faraday::Error => e
    Failbot.report!(e, app: "github-zuora")
    @_invoice = nil
  end

  sig { returns(String) }
  def next_billing_date_or_latest_bill
    if this_business.latest_bill
      this_business.latest_bill[:due_date].strftime("%B %d, %Y")
    else
      next_date = this_business.next_billing_date(with_dunning: true)
      next_date ? next_date.strftime("%B %d, %Y") : ""
    end
  end

  sig { returns(Float) }
  def latest_bill_amount
    # return the float representation of the latest bill instead of returning a formatted currency
    # so we can align with our front-end money formatting logic
    this_business.latest_bill_balance.to_f
  end

  sig { returns(Float) }
  memoize def prepaid_credit_balance
    this_business.customer&.credit_balance.to_f
  end

  sig { returns(T::Boolean) }
  def has_past_prepaid_credits?
    Billing::PrepaidMeteredUsageRefill.where(owner: this_business).exists?
  end

  # The GraphQL query that powers the Repository picker enforces CAP filtering and we need to prompt the user
  # to authenticate in order to see all of their repositories. Only Org owners are able to set budgets and cost centers
  # on repositories which is why we limit the viewer role to "owner".
  sig { returns(ActiveRecord::Relation) }
  memoize def set_organizations
    @organizations ||= T.let([], T.nilable(T::Array[Organization]))
    @organizations = this_business.filtered_organizations(viewer: current_user, viewer_role: "owner")
  end

  sig { returns(T.nilable(String)) }
  def admin_role
    if this_business.billing_manager?(current_user)
      "billing_manager"
    elsif this_business.owner?(current_user)
      "owner"
    elsif this_business.user_is_owner_of_owned_org?(current_user)
      "enterprise_org_owner"
    end
  end

  sig { returns(T.nilable(T::Boolean)) }
  def load_discount
    all_params.dig(:loadDiscount)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def usage_filter_params
    all_params.except(:loadDiscount)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def all_params
    params.except(:slug).permit(:customer_id, :period, :product, :sku, :query, :group, :loadDiscount, :page).to_h.symbolize_keys
  end

  sig { returns(String) }
  def customer_id
    this_business.customer_id.to_s
  end

  sig { void }
  def require_business_access
    T.bind(self, Businesses::BillingsController)
    business_access_required(allow_org_owners: true)
  end

  sig { void }
  def ensure_customer
    render_404 unless this_business.customer&.persisted?
  end
end
