# typed: strict
# frozen_string_literal: true

class Billing::Zuora::HostedPaymentsPage
  SPAMMY_MESSAGE = "You cannot add or update a payment method because your account has been flagged. If you believe this is a mistake, contact support"
  RSA_SIGNATURE_GENERATION_ERROR = "We are having trouble contacting our credit cards processing provider. Please use PayPal or try again later."
  GENERIC_PROCESSOR_DECLINED_ERROR_MESSAGE = "The credit card was declined by the payment processor, please verify the card's information. If the problem persists, please contact the card's issuer."

  COPILOT_SIGNATURE_VIEW_CONTEXT = "COPILOT"
  SPONSORS_SIGNATURE_VIEW_CONTEXT = "SPONSORS"
  PLAN_UPGRADE_SIGNATURE_VIEW_CONTEXT = "PLAN_UPGRADE"
  BILLING_SETTINGS_SIGNATURE_VIEW_CONTEXT = "BILLING_SETTINGS"
  BUSINESS_SELF_SERVE_SIGNATURE_VIEW_CONTEXT = "BUSINESS_SELF_SERVE"
  MARKETPLACE_SIGNATURE_VIEW_CONTEXT = "MARKETPLACE"
  COUPONS_SIGNATURE_VIEW_CONTEXT = "COUPONS"
  ORGANIZATION_SIGNUP_SIGNATURE_VIEW_CONTEXT = "ORGANIZATION_SIGNUP"
  SUBSCRIPTION_ITEMS_CHANGE_DURATION_SIGNATURE_VIEW_CONTEXT = "SUBSCRIPTION_ITEMS_CHANGE_DURATION"
  SIGNATURE_VIEW_CONTEXTS = T.let([
    COPILOT_SIGNATURE_VIEW_CONTEXT,
    SPONSORS_SIGNATURE_VIEW_CONTEXT,
    PLAN_UPGRADE_SIGNATURE_VIEW_CONTEXT,
    BILLING_SETTINGS_SIGNATURE_VIEW_CONTEXT,
    BUSINESS_SELF_SERVE_SIGNATURE_VIEW_CONTEXT,
    MARKETPLACE_SIGNATURE_VIEW_CONTEXT,
    COUPONS_SIGNATURE_VIEW_CONTEXT,
    ORGANIZATION_SIGNUP_SIGNATURE_VIEW_CONTEXT,
    SUBSCRIPTION_ITEMS_CHANGE_DURATION_SIGNATURE_VIEW_CONTEXT,
  ].freeze, T::Array[String])

  ERROR_MESSAGES = T.let({
    rsa_signature_generation_error: RSA_SIGNATURE_GENERATION_ERROR,
    processor_declined_error: GENERIC_PROCESSOR_DECLINED_ERROR_MESSAGE,
    attempts_exceeded_limit_error: "You have reached the attempts limit. Please refresh the page and try again."
  }, T::Hash[Symbol, String])

  THEMES = T.let({
    invoices: [ColorMode::LIGHT],
    settings_compact: [ColorMode::LIGHT, ColorMode::DARK, ColorMode::AUTO],
    settings_regular: [ColorMode::LIGHT, ColorMode::DARK, ColorMode::AUTO],
    sign_up: [ColorMode::LIGHT],
  }, T::Hash[Symbol, T::Array[String]])

  # Zuora Payment Pages 2.0
  #
  # https://knowledgecenter.zuora.com/Billing/Billing_and_Payments/LA_Hosted_Payment_Pages/B_Payment_Pages_2.0
  #
  # This class knows how to generate client params for Zuora Payment Pages 2.0.
  #
  # page_name - Page name. One of THEMES.keys. Used to determine the Zuora page ID.
  # target - Currently logged in target (user/org/business) that will view the rendered payment page
  # account_id - Optional argument of the Zuora account ID to link the new payment method after verification
  # manual_payment - True indicates that this is a one-time payment transaction
  # color_theme - Parent page color theme. One of ColorMode constants. Nil indicates to use the default theme.
  # host - Parent page host. Used when given page supports running on githubpreview.dev (Codespaces preview URL).
  # payment_gateway - Optional String payment gateway to use for the payment
  # invoices - Oprional Array of Zuora invoice number Strings for manual payments (e.g. ["INV0001", "INV0002"])
  sig do
    params(
      page_name: Symbol,
      target: Billing::Types::Account,
      account_id: T.nilable(String),
      manual_payment: T::Boolean,
      color_theme: T.nilable(ColorMode),
      host: T.nilable(String),
      payment_gateway: T.nilable(String),
      invoices: T.nilable(T::Array[String])
    ).void
  end
  def initialize(
    page_name:,
    target:,
    account_id: nil,
    manual_payment: false,
    color_theme: nil,
    host: nil,
    payment_gateway: nil,
    invoices: nil
  )
    @page_name = page_name
    @target = target
    @account_id = T.let(
      manual_payment ? T.must(target.customer).zuora_account_id : account_id,
      T.nilable(String)
    )
    @manual_payment = manual_payment
    @color_theme = color_theme
    @host = host
    @payment_gateway = payment_gateway
    @invoices = invoices
  end

  # Generates the params for the Zuora Payment Pages 2.0 form
  #
  # Returns a hash compatible with the shape specified in the Zuora documentation:
  # https://knowledgecenter.zuora.com/Billing/Billing_and_Payments/LA_Hosted_Payment_Pages/B_Payment_Pages_2.0/F_Client_Parameters_for_Payment_Pages_2.0
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def params
    if target.spammy?
      return error_response(SPAMMY_MESSAGE)
    end

    if target.has_any_trade_restrictions?
      return error_response(TradeControls::Notices.notice_as_plaintext(:user_account_restricted))
    end

    rsa_signature = ::Billing::Zuora::Signature::RSA.generate(
      uri: GitHub.zuora_payment_page_uri,
      page_id: page_id,
      account_id: account_id
    )
    unless rsa_signature
      return error_response(RSA_SIGNATURE_GENERATION_ERROR)
    end

    GitHub.dogstats.increment("billing.hosted_payment_page", tags: ["page_name:#{page_name}", "color_theme:#{color_theme}", "host:#{host}"])

    params = {
      id: page_id,
      key: rsa_signature.key,
      signature: rsa_signature.signature,
      tenantId: rsa_signature.tenant_id,
      token: rsa_signature.token,
      url: GitHub.zuora_payment_page_uri,
      countryBlackList: TradeControls::Countries.billing_address_blacklist_alpha3,
      paymentGateway: payment_gateway || ::Billing::Zuora::PaymentGateway.for(target, type: :credit_card),
      style: "inline",
      submitEnabled: "true",
      doPayment: manual_payment,
    }.merge(prefill_credit_card_details(rsa_signature))

    params[:documents] = documents.to_json if documents.present?
    params[:field_accountId] = account_id if account_id

    params
  end

  private

  sig { returns(Symbol) }
  attr_reader :page_name
  sig { returns(Billing::Types::Account) }
  attr_reader :target
  sig { returns(T.nilable(String)) }
  attr_reader :account_id
  sig { returns(T::Boolean) }
  attr_reader :manual_payment
  sig { returns(T.nilable(ColorMode)) }
  attr_reader :color_theme
  sig { returns(T.nilable(String)) }
  attr_reader :host
  sig { returns(T.nilable(String)) }
  attr_reader :payment_gateway
  sig { returns(T.nilable(T::Array[String])) }
  attr_reader :invoices

  sig { returns(String) }
  def page_id
    themes = THEMES[page_name]

    raise ArgumentError, "Invalid page name #{page_name}" unless themes

    color_theme = themes.include?(@color_theme) ? @color_theme : themes.first
    host = Rails.env.development? && @host != nil && @host.end_with?(".githubpreview.dev", ".app.github.dev") ? "preview" : "default"
    GitHub.send("zuora_#{page_name}_#{color_theme}_#{host}_payment_page_id")
  end

  sig { params(message: String).returns({ error: String }) }
  def error_response(message)
    {
      error: message,
    }
  end

  sig do
    params(
      rsa_signature: ::Billing::Zuora::Signature::RSA
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def prefill_credit_card_details(rsa_signature)
    params = development_credit_card_details(rsa_signature)
    return params unless target.has_saved_trade_screening_record?

    billing_contact = target.billing_contact
    params[:prepopulate] ||= {}
    params[:prepopulate].merge!(
      creditCardAddress1: billing_contact.address1,
      creditCardCountry: billing_contact.country.alpha3,
      creditCardState: billing_contact.region,
      creditCardCity: billing_contact.city,
      creditCardPostalCode: billing_contact.postal_code,
      creditCardHolderName: billing_contact.fullname,
    )

    params
  end

  sig do
    params(
      rsa_signature: ::Billing::Zuora::Signature::RSA
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def development_credit_card_details(rsa_signature)
    return {} unless Rails.env.development?

    {
      prepopulate: {
        creditCardNumber: rsa_signature.public_encrypt("4111111111111111"),
        creditCardExpirationMonth: rsa_signature.public_encrypt("01"),
        creditCardExpirationYear: rsa_signature.public_encrypt("2040"),
        cardSecurityCode: rsa_signature.public_encrypt("000"),
        creditCardAddress1: "88 Colin P Kelly Jr St",
        creditCardCountry: "USA",
        creditCardState: "California",
        creditCardCity: "San Francisco",
        creditCardPostalCode: "94107",
        creditCardHolderName: "Mona Lisa",
      },
    }
  end

  sig { returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
  def documents
    return nil unless manual_payment

    invoices = self.invoices
    invoices_to_pay = if invoices.present?
      invoices
    else
      zuora_account_id = target.customer&.zuora_account_id
      return nil unless zuora_account_id.present?

      Billing::Zuora::Invoice.open_invoices_for_account(zuora_account_id, posted_only: true).map(&:invoice_number)
    end

    invoices_to_pay.map { |invoice| { type: "invoice", ref: invoice } }
  end
end
