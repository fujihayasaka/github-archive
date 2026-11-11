# typed: strict
# frozen_string_literal: true

class Billing::Zuora::PaymentAuthorization

  class CreateResponse < T::Struct

    include GitHub::Memoizer

    const :success, T::Boolean

    # Fields when success is true
    const :gateway_order_id, T.nilable(String), name: "gatewayOrderId"
    const :result_code, T.nilable(String), name: "resultCode"
    const :result_message, T.nilable(String), name: "resultMessage"
    const :transaction_id, T.nilable(String), name: "transactionId"

    # Fields when success is false
    const :process_id, T.nilable(String), name: "processId"
    const :reasons, T::Array[T::Hash[String, String]], default: []
    const :request_id, T.nilable(String), name: "requestId"

    sig { returns(T::Boolean) }
    def card_error?
      !success && parsed_processor_response_code == "402"
    end

    sig { returns(T::Boolean) }
    def success?
      result_code == "0"
    end

    # This is the error code from Zuora, if applicable.
    sig { returns(T.nilable(Integer)) }
    def parsed_error_code
      success ? nil : parsed_errors["code"]
    end

    # This is the error message from Zuora, if applicable.
    sig { returns(T.nilable(String)) }
    def parsed_error_message
      success ? nil : parsed_errors["message"]
    end

    # This is the response code from the payment processor (e.g. Stripe), if applicable.
    sig { returns(T.nilable(String)) }
    def parsed_processor_response_code
      success ? result_code : parsed_errors["gatewayErrorCode"]
    end

    # This is the response message from the payment processor (e.g. Stripe), if applicable.
    sig { returns(T.nilable(String)) }
    def parsed_processor_response_message
      success ? result_message : parsed_errors["gatewayErrorMessage"]
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def log_context
      if success
        {
          "gh.billing.zuora.payment_authorization.success": success,
          "gh.billing.zuora.payment_authorization.gateway_order_id": gateway_order_id,
          "gh.billing.zuora.payment_authorization.result_code": result_code,
          "gh.billing.zuora.payment_authorization.result_message": result_message,
          "gh.billing.zuora.payment_authorization.transaction_id": transaction_id,
        }
      else
        {
          "gh.billing.zuora.payment_authorization.success": success,
          "gh.billing.zuora.payment_authorization.parsed_error_code": parsed_error_code,
          "gh.billing.zuora.payment_authorization.parsed_error_message": parsed_error_message,
          "gh.billing.zuora.payment_authorization.parsed_processor_response_code": parsed_processor_response_code,
          "gh.billing.zuora.payment_authorization.parsed_processor_response_message": parsed_processor_response_message,
          "gh.billing.zuora.payment_authorization.process_id": process_id,
          "gh.billing.zuora.payment_authorization.reasons": reasons.to_json,
          "gh.billing.zuora.payment_authorization.request_id": request_id,
        }
      end
    end

    private

    sig do
      returns({
        "code" => T.nilable(Integer),
        "message" => T.nilable(String),
        "gatewayErrorCode" => T.nilable(String),
        "gatewayErrorMessage" => T.nilable(String)
      })
    end
    memoize def parsed_errors
      if success
        return { "code" => nil, "message" => nil, "gatewayErrorCode" => nil, "gatewayErrorMessage" => nil }
      end

      reason = T.must(reasons.first)
      message = T.must(reason["message"])

      # The response structure differs depending on whether the root cause is a Zuora error or a gateway error.
      # - Zuora Error:   {"success" => false, "reasons" => [{"code" => 52210020, "message" => "The payment method does not exist."}]}
      # - Gateway Error: {"success" => false, "reasons" => [{"code" => 52210030, "message" => "gatewayErrorCode=402, gatewayErrorMessage=[card_error/incorrect_number/incorrect_number] Your card number is incorrect."}]}
      parsed_error_message =
        if message.include?("gatewayErrorMessage")
          Hash[
            message.split(", ").map do |pair|
              k, v = pair.split("=", 2)
              [k, v]
            end
          ]
        else
          {}
        end

      {
        "code" => reason["code"]&.to_i,
        "message" => reason["message"],
        "gatewayErrorCode" => parsed_error_message["gatewayErrorCode"],
        "gatewayErrorMessage" => parsed_error_message["gatewayErrorMessage"],
      }
    end
  end

  sig do
    params(payment_method_id: String, account_id: String, amount: Billing::Money, gateway_order_id: String)
    .returns(CreateResponse)
  end
  def self.create(payment_method_id:, account_id:, amount:, gateway_order_id: "")
    response = GitHub.zuorest_client.create_authorization(payment_method_id, {
      accountId: account_id,
      amount: amount.dollars,
      gatewayOrderId: gateway_order_id
    })

    GitHub.logger.info(
      "code.namespace": "Billing::Zuora::PaymentAuthorization",
      "code.function": __method__,
      "gh.billing.zuora.payment_authorization.payment_method_id": payment_method_id,
      "gh.billing.zuora.payment_authorization.account_id": account_id,
      "gh.billing.zuora.payment_authorization.amount": amount.dollars,
      "gh.billing.zuora.payment_authorization.gateway_order_id": gateway_order_id,
      "gh.billing.zuora.payment_authorization.response": response,
      "gh.billing.zuora.payment_authorization.success": response["success"]
    )

    CreateResponse.from_hash(response)
  end
end
