# typed: true
# frozen_string_literal: true

class Billing::Zuora::PaymentMethod
  class NoFingerprintPresentError < StandardError; end

  sig { params(id: String).returns(T.nilable(Billing::Zuora::PaymentMethod)) }
  def self.find(id)
    response = GitHub.zuorest_client.get_payment_method(id)
    new(response)
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
    attributes["Id"]
  end

  sig { returns(T.nilable(String)) }
  def card_holder_name
    attributes["CreditCardHolderName"]
  end

  sig { returns(T.nilable(String)) }
  def masked_number
    attributes["CreditCardMaskNumber"]
  end

  sig { returns(T.nilable(Integer)) }
  def expiration_month
    attributes["CreditCardExpirationMonth"]
  end

  sig { returns(T.nilable(Integer)) }
  def expiration_year
    attributes["CreditCardExpirationYear"]
  end

  sig { returns(T.nilable(String)) }
  def card_type
    attributes["CreditCardType"]
  end

  sig { returns(String) }
  def type
    attributes["Type"]
  end

  sig { returns(T.nilable(String)) }
  def postal_code
    attributes["CreditCardPostalCode"]
  end

  sig { returns(T.nilable(String)) }
  def state
    attributes["CreditCardState"]
  end

  sig { returns(T.nilable(String)) }
  def paypal_email
    attributes["PaypalEmail"]
  end

  sig { returns(Integer) }
  def consecutive_failures
    attributes["NumConsecutiveFailures"]
  end

  sig { returns(T.nilable(String)) }
  def fingerprint
    if attributes["TokenId"]
      braintree_payment_method_id = JSON.parse(attributes["TokenId"]).values.first
      Braintree::PaymentMethod.find(braintree_payment_method_id).unique_number_identifier
    else
      response = GitHub.zuorest_client.query_action({
        queryString: "select responsestring from paymentmethodtransactionlog where paymentmethodid = '#{id}' limit 1",
      })

      payment_method_id = response.dig("records", 0, "ResponseString").match(/payment_method\"\: \"(\w+)\"/)&.captures&.dig(0)
      fingerprint = retrieve_card_fingerprint_with_fallback(payment_method_id)
      raise Billing::Zuora::PaymentMethod::NoFingerprintPresentError if fingerprint.nil?

      fingerprint
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
