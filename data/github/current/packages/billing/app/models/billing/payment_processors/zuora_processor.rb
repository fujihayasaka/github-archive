# typed: strict
# frozen_string_literal: true

class Billing::PaymentProcessors::ZuoraProcessor < Billing::PaymentProcessors::PaymentProcessor
  SLUG = "zuora"

  sig do
    params(
      customer_id: T.nilable(String),
      gateway: Billing::Zuora::PaymentGateway
    ).void
  end
  def initialize(customer_id, gateway:)
    super
    @gateway_must = T.let(T.must(@gateway), Billing::Zuora::PaymentGateway)
  end

  sig do
    override
      .params(
        payment_details: ::Billing::PaymentProcessorPaymentDetails,
        blk: T.nilable(T.proc.params(arg0: ::Billing::PaymentProcessorRecord).void)
      ).returns(GitHub::Billing::Result)
  end
  def update_payment_details(payment_details, &blk)
    return GitHub::Billing::Result.failure("No customer record") if customer_id.blank?
    unless payment_details.zuora_payment_details?
      return GitHub::Billing::Result.failure("No payment details present")
    end

    response = update_customer_contact(payment_details: payment_details)
    unless response[:success]
      return GitHub::Billing::Result.failure("Unable to update payment method: please review your billing address under \"Payment information\"")
    end

    update_customer_params = {}
    if payment_details.zuora_hosted_payments_page_details?
      payment_method_id = payment_details.zuora_payment_method_id
    else
      response = create_paypal_payment_method(payment_details)

      return GitHub::Billing::Result.failure("Unable to update payment method") unless response[:success]
      payment_method_id = response[:payment_method_id]
    end

    zuora_payment_method = ::Billing::Zuora::PaymentMethod.find(payment_method_id)
    unless zuora_payment_method
      return GitHub::Billing::Result.failure("Payment method not found")
    end

    gateway.type = zuora_payment_method.credit_card? ? :credit_card : :paypal
    update_customer_params.merge!(
      AutoPay: payment_details.auto_pay,
      DefaultPaymentMethodId: zuora_payment_method.id,
      PaymentGateway: gateway.name,
    )
    response = update_customer_account(update_customer_params)
    result = GitHub::Billing::Result.from_zuora({ success: response["Success"] })
    if result.success?
      record = ::Billing::PaymentProcessorRecord.new(customer_id: customer_id)
      record.token = zuora_payment_method.id
      if zuora_payment_method.credit_card?
        record.masked_number = zuora_payment_method.masked_number
        record.expiration_month = zuora_payment_method.expiration_month
        record.expiration_year = zuora_payment_method.expiration_year
        record.card_type = zuora_payment_method.card_type
        record.postal_code = zuora_payment_method.postal_code
        record.region = zuora_payment_method.state
        record.country_code_alpha3 = payment_details.country_code_alpha3
        record.unique_number_identifier = zuora_payment_method.fingerprint
      elsif zuora_payment_method.paypal?
        record.postal_code = payment_details.postal_code
        record.region = payment_details.region
        record.country_code_alpha3 = payment_details.country_code_alpha3
        record.paypal_email = zuora_payment_method.paypal_email
      end

      yield record if block_given?

      result.record = record
    end

    result
  end

  sig { override.returns(T::Boolean) }
  def clear_payment_details
    customer_id = self.customer_id
    return false if customer_id.blank?
    ZuoraDeleteCardsFromAccountJob.perform_now(customer_id)
    true # Let the job retry in case of failure
  end

  sig { override.params(payment_details: ::Billing::PaymentProcessorPaymentDetails).returns(T::Hash[Symbol, T.untyped]) }
  def update_customer_contact(payment_details:)
    account_response = GitHub.zuorest_client.get_account(customer_id)
    contact_params = {
      AccountId: account_response["Id"],
      Country: payment_details.country_code_alpha3,
      PostalCode: payment_details.postal_code,
      State: payment_details.region,
    }
    responses = GitHub.dogstats.time("zuora.timing.action_contact_update") do
      GitHub.zuorest_client.update_action({
        objects: [
          { Id: account_response["SoldToId"] }.merge!(contact_params),
          { Id: account_response["BillToId"] }.merge!(contact_params),
        ],
        type: "Contact",
      })
    end

    if responses.all? { |response| response["Success"] }
      { success: true }
    else
      errors = responses.select { |response| !response["Success"] }.flat_map { |response| response["Errors"] }
      { success: false, errors: errors }
    end
  rescue Zuorest::HttpError => e
    Failbot.report!(e, app: "github-zuora")
    { success: false }
  end

  private

  sig { returns(Billing::Zuora::PaymentGateway) }
  def gateway
    @gateway_must
  end

  sig { params(payment_details: ::Billing::PaymentProcessorPaymentDetails).returns(T::Hash[Symbol, T.untyped]) }
  def create_paypal_payment_method(payment_details)
    Billing::ZuoraPaypal.create_payment_method(
      account_id: T.must(customer_id),
      paypal_nonce: payment_details.paypal_nonce,
    )
  rescue Billing::ZuoraPaypal::Error => e
    braintree_response = Braintree::Customer.create({ id: customer_id, first_name: payment_details.account_name })
    if braintree_response.success?
      retry
    end

    Failbot.report(e, { "gh.customer.id" => customer_id, "gh.billing.braintree.response.message" => "#{braintree_response.message} - #{braintree_response.errors.inspect}" })

    { success: false }
  end

  sig do
    params(attributes: T::Hash[T.any(Symbol, String), T.untyped])
      .returns(T::Hash[T.any(Symbol, String), T.untyped])
  end
  def update_customer_account(attributes)
    # This is from:
    # https://community.zuora.com/t5/API/How-to-set-a-field-to-NULL-via-REST-API/m-p/15290/highlight/true#M692
    # it's certainly not very RESTy
    GitHub.dogstats.time("zuora.timing.action_account_update") do
      GitHub.zuorest_client.update_action({
        "objects": [
          {
            "Id": customer_id,
          }.merge!(attributes),
        ],
        "type": "Account",
      }).first
    end
  end
end
