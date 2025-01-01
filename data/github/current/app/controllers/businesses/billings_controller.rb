# typed: strict
# frozen_string_literal: true

class Businesses::BillingsController < Businesses::BusinessController
  include GitHub::Memoizer
  include BillingSettingsHelper
  include ReactHelper
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

  before_action -> do
    T.bind(self, Businesses::BillingsController)

    business_access_required(allow_org_owners: true)
  end
  before_action :ensure_billing_enabled
  before_action :ensure_vnext_enabled

  sig { void }
  def show
    current_user = T.must(self.current_user)
    begin
      notification = Billing::Notifications::CustomerBudgetsNotifications.new(owner: this_business, actor: current_user)
      banners = notification.budget_threshold_banners(actor: current_user)
    rescue => e # rubocop:todo Lint/GenericRescue
      Failbot.report(e)
      GitHub.dogstats.increment("billing_platform.budget_banner_error")
      banners = []
    end

    react_page_payload = {
      customer: customer_payload(this_business),
      customer_selections: usage_customer_selections(this_business),
      period_selections: usage_period_selections,
      admin_roles: admin_roles(this_business),
      enabled_products: enabled_products,
      multi_tenant: GitHub.multi_tenant_enterprise?,
      budget_alert_details: banners.map do |banner|
        {
          text: banner.text,
          variant: banner.variant.to_s,
          dismissable: banner.dismissible?,
          dismiss_link: banner.dismissal_path,
          budget_id: banner.budget_uuid,
        }
      end,
      showVolumeLicenseSpendTile: this_business.show_volume_license_spend_tile?(current_user),
      showPaymentDueTile: this_business.show_payment_due_tile?(current_user),
      showLatestInvoiceTile: this_business.show_past_invoices_tab?(current_user) && invoice.present?,
      show_new_usage_chart: this_business.feature_enabled?(:billing_platform_accessibility_usage_chart),
      taxDisclaimer: tax_disclaimer(this_business),
      showPrepaidCredits: this_business.feature_enabled?(:billing_vnext_prepaid_credits) && has_past_prepaid_credits?,
    }

    if react_page_payload[:showVolumeLicenseSpendTile]
      react_page_payload[:volumeLicenseSpendTileData] = volume_license_spend
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

    render_react_app(
      payload: react_page_payload,
      page_data: { selected_link: :business_billing_vnext_overview },
      title: "Billing Overview",
      layout_locals_generator: -> {
        {
          banner_component: view_context.render(
            Billing::Settings::EnterpriseContractEarlyExpirationBannerComponent.new(business: this_business, current_user: current_user),
          ),
        }
      },
      layout: "react_business",
      ssr: true
    )
  end

  private

  sig { returns(T.nilable(::Billing::Zuora::Invoice)) }
  def invoice
    return @_invoice if defined?(@_invoice)

    invoices ||= T.let(Billing::Zuora::Invoice.invoices_for_account(this_business.customer&.zuora_account_id.to_s)
      .select(&:posted?)
      .reject(&:suppress_from_customer_view?)
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
    return this_business.latest_bill[:due_date].strftime("%B %d, %Y") if this_business.latest_bill
    this_business.next_billing_date(with_dunning: true).strftime("%B %d, %Y")
  end

  sig { returns(Float) }
  def latest_bill_amount
    # return the float representation of the latest bill instead of returning a formatted currency
    # so we can align with our front-end money formatting logic
    this_business.latest_bill_balance.to_f
  end

  sig { returns(Billing::Platform::Api::Client) }
  def billing_platform_client
    Billing::Platform::Api::Client.new
  end

  sig { returns(Float) }
  memoize def prepaid_credit_balance
    this_business.customer&.credit_balance.to_f
  end

  sig { returns(T::Boolean) }
  def has_past_prepaid_credits?
    Billing::PrepaidMeteredUsageRefill.where(owner: this_business).exists?
  end

  sig { returns(Float) }
  def ghe_volume_license_spend
    seats = this_business.purchased_enterprise_licenses
    manage_seats = ::Business::ManageSeats.new(business: this_business, new_seats: seats)

    # return the float representation of the seat price instead of returning a formatted currency
    # so we can align with our front-end money formatter
    manage_seats.current_price.to_f
  end

  sig { returns(Float) }
  def ghas_volume_license_spend
    if !this_business.advanced_security_purchased?
      return 0.0
    end
    ghas_seats = this_business.advanced_security_license.seats
    if ghas_seats.zero?
      return 0.0
    end

    monthly_ghas_base_price = 49.0
    formatted_base_price = Billing::Money.new((monthly_ghas_base_price * 100).to_d)
    (ghas_seats * formatted_base_price).to_f
  end

  sig { returns(Float) }
  def ghas_volume_license_spend_yearly
    ghas_volume_license_spend * 12
  end

  class VolumeLicenseData < T::Struct
    prop :IsSeparateDisplayCard, T::Boolean
    prop :gheAndGhas, T::Hash[Symbol, T.untyped]
    prop :ghe, T::Hash[Symbol, T.untyped]
    prop :ghas, T::Hash[Symbol, T.untyped]
    prop :IsInvoiced, T::Boolean
  end

  sig { returns(Businesses::BillingsController::VolumeLicenseData) }
  def volume_license_spend
    data = VolumeLicenseData.new(IsSeparateDisplayCard: false, gheAndGhas: { period: "", spend: 0.0 }, ghe: { period: "", spend: 0.0 }, ghas: { period: "", spend: 0.0 }, IsInvoiced: this_business.invoiced?)
    if this_business.advanced_security_purchased?
      if this_business.invoiced?
        data.gheAndGhas = { period: "per year", spend: ghe_volume_license_spend + ghas_volume_license_spend_yearly }
      else
        # self-serve businesses
        if this_business.monthly_plan?
          data.gheAndGhas = { period: "per month", spend: ghe_volume_license_spend + ghas_volume_license_spend }
        else
          data.IsSeparateDisplayCard = true
          data.ghe = { period: "per year", spend: ghe_volume_license_spend }
          data.ghas = { period: "per month", spend: ghas_volume_license_spend }
        end
      end
    else
      data.gheAndGhas = { period: this_business.monthly_plan? ? "per month" : "per year", spend: ghe_volume_license_spend }
    end
    data
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

  sig { void }
  def ensure_vnext_enabled
    render_404 unless this_business.customer&.billed_via_billing_platform?
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
    params.except(:slug).permit(:customer_id, :period, :product, :query, :group, :loadDiscount, :page).to_h.symbolize_keys
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def all_products
    products_response = billing_platform_client.get_all_products
    products = if products_response.is_a?(::Billing::Platform::Api::Error)
      []
    else
      products_response[:products]
    end
    products
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def enabled_products
    enabled_products = this_business.customer.products_billed_via_billing_platform
    # enabled_products is an array of strings, so we need to get all products from bp since we need friendly names for the UI
    all_products.select { |product| enabled_products.include?(product[:name]) }
  end

  sig { returns(String) }
  def customer_id
    this_business.customer_id.to_s
  end
end
