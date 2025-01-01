# typed: strict
# frozen_string_literal: true

module Billing
  class UpdatePaymentMethodInStripeJob < BillingJob
    include GitHub::Billing::ZuoraRateLimitHandler

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
      retry_on(error, wait: :polynomially_longer) do |_job, error|
        Failbot.report(error)
      end
    end

    rescue_from(Zuorest::TooManyRequestsError) do |error|
      T.bind(self, UpdatePaymentMethodInStripeJob)

      zuora_rate_limit_handler(self, error)
    end

    sig { params(payment_method_id: Integer).void }
    def perform(payment_method_id)
      dotcom_payment_method = PaymentMethod.find_by(id: payment_method_id)
      return unless dotcom_payment_method.present?

      stripe_payment_method = get_stripe_payment_method(dotcom_payment_method)
      return unless stripe_payment_method.present?
      return unless T.unsafe(stripe_payment_method).customer.nil?

      dotcom_customer_id = dotcom_payment_method.customer&.id
      return unless dotcom_customer_id.present?

      log_context = {
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.billing.customer.id" => dotcom_customer_id,
        "gh.billing.payment_method.id" => dotcom_payment_method.id,
        "gh.billing.stripe.payment_method.id" => stripe_payment_method.id,
      }

      stripe_customer_id = get_stripe_customer_id(dotcom_customer_id)
      if stripe_customer_id.blank?
        GitHub.logger.info("stripe customer id not found", log_context)
        stripe_customer_id = Billing::UpdateCustomerInStripeJob.new.perform(dotcom_customer_id)&.id
      end

      return unless stripe_customer_id.present?

      stripe_payment_method = ::Stripe::PaymentMethod.attach(stripe_payment_method.id, { customer: stripe_customer_id }, { api_key: GitHub.stripe_v3_api_key })

      GitHub.dogstats.increment("billing.update_payment_method_in_stripe.payment_method_attached")
      GitHub.logger.info("attached stripe payment method to customer",
        log_context.merge("gh.billing.stripe.payment_method.customer" => stripe_payment_method.customer))
    end

    private

    sig { params(dotcom_payment_method: PaymentMethod).returns(T.nilable(::Stripe::PaymentMethod)) }
    def get_stripe_payment_method(dotcom_payment_method)
      stripe_payment_method_id = get_stripe_payment_method_id(dotcom_payment_method.payment_token)
      return unless stripe_payment_method_id.present?

      log_context = {
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.billing.payment_method.id" => dotcom_payment_method.id,
        "gh.billing.stripe.payment_method.id" => stripe_payment_method_id
      }

      stripe_payment_method = ::Stripe::PaymentMethod.retrieve(stripe_payment_method_id, { api_key: GitHub.stripe_v3_api_key })

      GitHub.dogstats.increment("billing.update_payment_method_in_stripe.payment_method_retrieved")
      GitHub.logger.info("payment method retrieved", log_context)

      stripe_payment_method
    rescue ::Stripe::InvalidRequestError => e
      # Stripe returns this error when the requested payment method does not exist
      GitHub.logger.error(e, log_context)
      nil
    end

    sig { params(zuora_payment_method_id: String).returns(T.nilable(String)) }
    def get_stripe_payment_method_id(zuora_payment_method_id)
      return if zuora_payment_method_id.blank? || zuora_payment_method_id == PaymentMethod::PAYMENT_TOKEN_CLEARED

      query = "select responsestring from paymentmethodtransactionlog where paymentmethodid = '#{zuora_payment_method_id}' limit 1"
      response = GitHub.zuorest_client.query_action queryString: query

      GitHub.dogstats.increment("billing.update_payment_method_in_stripe.query_stripe_payment_method_id", tags: ["found:#{response["records"].any?}"])
      GitHub.logger.info(
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.billing.zuora.payment_method.id" => zuora_payment_method_id,
        "gh.billing.zuora.response" => response,
      )

      response.dig("records", 0, "ResponseString")&.match(/payment_method\"\: \"(\w+)\"/)&.captures&.dig(0)
    end

    sig { params(dotcom_customer_id: Integer).returns(T.untyped) }
    def get_stripe_customer_id(dotcom_customer_id)
      key = "stripe_customer_id_for_dotcom_customer_#{dotcom_customer_id}"
      Billing::Kv.store.get(key).value!
    end
  end
end
