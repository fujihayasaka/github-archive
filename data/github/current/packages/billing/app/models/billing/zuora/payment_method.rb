# typed: strict
# frozen_string_literal: true

class Billing::Zuora::PaymentMethod
  include GitHub::Memoizer

  class NoFingerprintPresentError < StandardError; end

  sig { params(id: String).returns(T.nilable(Billing::Zuora::PaymentMethod)) }
  def self.find(id)
    response = GitHub.zuorest_client.get_payment_method_new(id)
    response["success"] ? new(response) : nil
  rescue Zuorest::HttpError => e
    Failbot.report!(e, app: "github-zuora")
    nil
  end

  sig { params(payment_method_attributes: T::Hash[String, T.untyped]).void }
  def initialize(payment_method_attributes)
    @attributes = payment_method_attributes
  end

  sig { returns(String) }
  def id
    attributes["id"]
  end

  sig { returns(T.nilable(String)) }
  def account_holder_name
    attributes.dig("accountHolderInfo", "accountHolderName")
  end

  sig { returns(T.nilable(String)) }
  def masked_number
    attributes["cardNumber"] || stripe_masked_number
  end

  sig { returns(T.nilable(Integer)) }
  def expiration_month
    attributes["expirationMonth"] || stripe_expiration_month
  end

  sig { returns(T.nilable(Integer)) }
  def expiration_year
    attributes["expirationYear"] || stripe_expiration_year
  end

  sig { returns(T.nilable(String)) }
  def card_type
    attributes["creditCardType"] || stripe_card_brand
  end

  CREDIT_CARD_TYPES = T.let(%w[CreditCard CreditCardReferenceTransaction].freeze, T::Array[String])

  sig { returns(String) }
  def type
    CREDIT_CARD_TYPES.include?(attributes["type"]) ? "CreditCard" : "PayPal"
  end

  sig { returns(T::Boolean) }
  def cc_reference?
    attributes["type"] == "CreditCardReferenceTransaction"
  end

  sig { returns(T.nilable(String)) }
  def account_holder_zip_code
    attributes.dig("accountHolderInfo", "zipCode")
  end
  alias_method :account_holder_postal_code, :account_holder_zip_code

  sig { returns(T.nilable(String)) }
  def account_holder_state
    attributes.dig("accountHolderInfo", "state")
  end
  alias_method :account_holder_region, :account_holder_state

  # Returns the alpha-2 country code of the credit card issuer country.
  # This is not always the same as the billing address country provided by the customer.
  sig { returns(T.nilable(String)) }
  def issuing_country_code
    attributes.dig("cardBinInfo", "issuingCountryCode")
  end
  alias_method :country, :issuing_country_code

  sig { returns(T.nilable(String)) }
  def paypal_email
    attributes["email"]
  end

  sig { returns(Integer) }
  def consecutive_failures
    attributes["numConsecutiveFailures"]
  end

  sig { returns(T.nilable(String)) }
  def fingerprint
    if payment_method = stripe_payment_method
      fingerprint = payment_method.card&.fingerprint
      raise Billing::Zuora::PaymentMethod::NoFingerprintPresentError if fingerprint.nil?
      fingerprint
    elsif payment_method = braintree_payment_method
      # This is only needed for a our legacy tests that use Braintree for credit cards
      payment_method.unique_number_identifier
    end
  rescue Billing::Zuora::PaymentMethod::NoFingerprintPresentError => e
    Failbot.report!(e, app: "github-zuora")
    nil
  end

  sig { returns(T::Boolean) }
  def credit_card?
    type == "CreditCard"
  end

  sig { returns(T::Boolean) }
  def paypal?
    !credit_card?
  end

  private

  sig { returns(T::Hash[String, T.untyped]) }
  attr_reader :attributes

  # Stripe card details fallback for CreditCardReferenceTransaction payment methods,
  # which don't include card number/expiration in the Zuora API response.
  STRIPE_BRAND_MAP = T.let({
    "visa" => "Visa",
    "mastercard" => "MasterCard",
    "amex" => "AmericanExpress",
    "discover" => "Discover",
    "jcb" => "JCB",
    "diners" => "Diners",
    "unionpay" => "UnionPay",
  }.freeze, T::Hash[String, String])

  sig { returns(T.nilable(String)) }
  def stripe_masked_number
    return unless cc_reference?

    last4 = stripe_payment_method&.card&.last4
    "************#{last4}" if last4
  end

  sig { returns(T.nilable(Integer)) }
  def stripe_expiration_month
    return unless cc_reference?

    stripe_payment_method&.card&.exp_month
  end

  sig { returns(T.nilable(Integer)) }
  def stripe_expiration_year
    return unless cc_reference?

    stripe_payment_method&.card&.exp_year
  end

  sig { returns(T.nilable(String)) }
  def stripe_card_brand
    return unless cc_reference?

    brand = stripe_payment_method&.card&.brand
    return unless brand

    STRIPE_BRAND_MAP[brand] || brand.capitalize
  end

  sig { returns(T.nilable(Stripe::PaymentMethod)) }
  memoize def stripe_payment_method
    payment_method_id = payment_gateway_response_string&.match(/payment_method\"\: \"(\w+)\"/)&.captures&.dig(0)
    return unless payment_method_id

    api_keys = [GitHub.stripe_v3_api_key, GitHub.stripe_api_key]
    stripe_payment_methods = api_keys.lazy.filter_map do |api_key|
      Stripe::PaymentMethod.retrieve(payment_method_id, { api_key: api_key })
    rescue Stripe::InvalidRequestError
      next if api_key != api_keys.last
      raise
    end

    stripe_payment_methods.first
  rescue Stripe::StripeError => e
    Failbot.report!(e, app: "github-zuora")
    nil
  end

  sig { returns(T.untyped) }
  memoize def braintree_payment_method
    token_id = payment_gateway_response_string&.match(/token_id=(\w+)/)&.captures&.dig(0)
    return unless token_id
    Braintree::PaymentMethod.find(token_id)
  rescue Braintree::NotFoundError => e
    Failbot.report!(e, app: "github-zuora")
    nil
  end

  sig { returns(T.nilable(String)) }
  memoize def payment_gateway_response_string
    response = GitHub.zuorest_client.query_action({
      queryString: "select responsestring from paymentmethodtransactionlog where paymentmethodid = '#{id}' limit 1",
    })
    response.dig("records", 0, "ResponseString")
  rescue Zuorest::HttpError => e
    Failbot.report!(e, app: "github-zuora")
    nil
  end
end
