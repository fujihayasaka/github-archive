# typed: strict
# frozen_string_literal: true

module Billing
  class CancelAuthorizationBillingTransactionJob < BillingJob

    include GitHub::Billing::ZuoraRateLimitHandler

    queue_as :cancel_authorization_hold

    retry_on_dirty_exit
    (Billing::Zuora::RETRYABLE_ERRORS + Billing::Braintree::RETRYABLE_ERRORS).each do |error|
      retry_on(error, wait: :polynomially_longer) do |_job, error|
        GitHub.dogstats.increment(
          "billing.cancel_authorization_billing_transaction_job.failed",
          tags: ["error:#{error.class.name}"],
        )
        Failbot.report(error, { "gh.job.name" => CancelAuthorizationBillingTransactionJob.name })
      end
    end

    rescue_from(Zuorest::TooManyRequestsError) do |error|
      T.bind(self, CancelAuthorizationBillingTransactionJob)

      zuora_rate_limit_handler(self, error)
    end

    class Metrics < T::Struct
      prop :response_code, String
      prop :response_message, String
      prop :success, T::Boolean
    end

    sig { params(billing_transaction_id: Integer).void }
    def perform(billing_transaction_id:)
      return unless billing_transaction = Billing::BillingTransaction.find_by(id: billing_transaction_id)
      return unless billing_transaction.is_authorization? && billing_transaction.pending_status_update? && billing_transaction.transaction_id.present?

      billable_entity = T.cast(billing_transaction.billable_entity, Billing::Types::Account)
      metrics = cancel_authorization(billable_entity: billable_entity, transaction: billing_transaction)

      instrument_authorization_transaction_cancelled(billable_entity: billable_entity, metrics: metrics, amount_in_cents: billing_transaction.amount_in_cents.to_i)

      if metrics.success
        with_write do
          billing_transaction.update!(last_status: :authorization_cancelled)
        end
      end
    end

    private

    sig { params(billable_entity: Billing::Types::Account, transaction: BillingTransaction).returns(Metrics) }
    def cancel_authorization(billable_entity:, transaction:)
      if transaction.zuora?
        cancel_zuora_authorization(billable_entity: billable_entity, transaction_id: transaction.transaction_id)
      else
        cancel_paypal_authorization(billable_entity: billable_entity, transaction_id: transaction.transaction_id)
      end
    end

    # We have to handle the response differently depending on if the request succeeded or errored
    #
    # If successful the response info is stored in response["resultCode"] and response["resultMessage"]
    # ex. response={"resultCode"=>"0", "resultMessage"=>"Approved"}
    #
    # If unsuccessful the response info is stored in an error message as a comma separated k=v string that we have to parse
    # ex. @error_message="gatewayErrorCode=402, gatewayErrorMessage=[card_error/card_declined/insufficient_funds] Your card has insufficient funds."
    sig { params(billable_entity: Billing::Types::Account, transaction_id: String).returns(Metrics) }
    def cancel_zuora_authorization(billable_entity:, transaction_id:)
      response = GitHub.zuorest_client.cancel_authorization("#{billable_entity.payment_method.payment_token}", {
        accountId: billable_entity.customer_zuora_account_id,
        transactionId: transaction_id,
      })
      result = GitHub::Billing::Result.from_zuora(response)

      # Sometimes Zuora will tell us the request was unsuccessful, but the response from Stripe will be a 200 "Approved"
      # Instead of relying on Zuora's success flag, we check the processor_response_code for 200 (Stripe) or 0 (Zuora)
      success = result.success? || response["processor_response_code"].to_s == "200" || response["processor_response_code"].to_s == "0"

      if success
        response_code = response["resultCode"]
        response_message = response["resultMessage"]
      else
        parsed_error_message = Hash[
          result.error_message.split(", ").map do |pair|
            k, v = pair.split("=", 2)
            [k, v]
          end
        ]

        response_code = parsed_error_message["gatewayErrorCode"],
        response_message = parsed_error_message["gatewayErrorMessage"]
      end

      Metrics.new(
        response_code: response_code || "",
        response_message: response_message || "",
        success: success,
      )
    end

    sig { params(billable_entity: Billing::Types::Account, transaction_id: String).returns(Metrics) }
    def cancel_paypal_authorization(billable_entity:, transaction_id:)
      response = ::Braintree::Transaction.void(transaction_id)
      Metrics.new(
        response_code: response.transaction&.processor_response_code || "",
        response_message: response.success? ? response.transaction.status : response.message,
        success: response.success?,
      )
    end

    sig { params(billable_entity: Billing::Types::Account, metrics: Metrics, amount_in_cents: Integer).void }
    def instrument_authorization_transaction_cancelled(billable_entity:, metrics:, amount_in_cents:)
      GitHub.dogstats.increment("billing.authorization_cancelled", tags: ["success:#{metrics.success}", "amount_in_cents:#{amount_in_cents}"])
      GlobalInstrumenter.instrument("billing.authorization_transaction_cancelled", {
        account: billable_entity,
        account_type: billable_entity.business? ? "business" : "user",
        payment_method: billable_entity.payment_method,
        success: metrics.success,
        declined: false,
        authorization_amount_in_cents: amount_in_cents,
        processor_response_code: metrics.response_code,
        processor_response: metrics.response_message,
      })
      GitHub.logger.info(
        "Billing authorization cancelled",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.billing.cancel_authorization.success": metrics.success,
        "gh.billing.cancel_authorization.processor_response_code": metrics.response_code,
        "gh.billing.cancel_authorization.processor_response_message": metrics.response_message,
      )
    end
  end
end
