# typed: strict
# frozen_string_literal: true

class Billing::Zuora::PaymentMethod
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
    attributes["cardNumber"]
  end

  sig { returns(T.nilable(Integer)) }
  def expiration_month
    attributes["expirationMonth"]
  end

  sig { returns(T.nilable(Integer)) }
  def expiration_year
    attributes["expirationYear"]
  end

  sig { returns(T.nilable(String)) }
  def card_type
    attributes["creditCardType"]
  end

  sig { returns(String) }
  def type
    attributes["type"] == "CreditCard" ? "CreditCard" : "PayPal"
  end

  sig { returns(T.nilable(String)) }
  def postal_code
    attributes.dig("accountHolderInfo", "zipCode")
  end

  sig { returns(T.nilable(String)) }
  def state
    attributes.dig("accountHolderInfo", "state")
  end

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
    response = GitHub.zuorest_client.query_action({
      queryString: "select responsestring from paymentmethodtransactionlog where paymentmethodid = '#{id}' limit 1",
    })
    payment_method_id = response.dig("records", 0, "ResponseString").match(/payment_method\"\: \"(\w+)\"/)&.captures&.dig(0)
    token_id = response.dig("records", 0, "ResponseString").match(/token_id=(\w+)/)&.captures&.dig(0)

    if payment_method_id
      fingerprint = retrieve_card_fingerprint_with_fallback(payment_method_id)
      raise Billing::Zuora::PaymentMethod::NoFingerprintPresentError if fingerprint.nil?
      fingerprint
    elsif token_id
      # This is only needed for a our legacy tests that use Braintree for credit cards
      Braintree::PaymentMethod.find(token_id).unique_number_identifier
    else
      raise Billing::Zuora::PaymentMethod::NoFingerprintPresentError
    end
  rescue Braintree::NotFoundError, Zuorest::HttpError, Billing::Zuora::PaymentMethod::NoFingerprintPresentError, Stripe::StripeError => e
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

  # Resolve Stripe credit card fingerprint with support for multiple API keys
  sig { params(payment_method_id: String).returns(T.nilable(String)) }
  def retrieve_card_fingerprint_with_fallback(payment_method_id)
    api_keys = [GitHub.stripe_v3_api_key, GitHub.stripe_api_key]

    stripe_payment_methods = api_keys.lazy.filter_map do |api_key|
      Stripe::PaymentMethod.retrieve(payment_method_id,
        { api_key: api_key }
      )
    rescue Stripe::InvalidRequestError
      next
    end

    stripe_payment_method = stripe_payment_methods.first
    return unless stripe_payment_method

    stripe_payment_method.card.fingerprint
  end
end
