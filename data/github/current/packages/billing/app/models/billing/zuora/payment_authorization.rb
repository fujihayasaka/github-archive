# typed: strict
# frozen_string_literal: true

class Billing::Zuora::PaymentAuthorization

  class CreateResponse < T::Struct

    include GitHub::Memoizer

    const :success, T::Boolean

    # Fields may not be present when success is false
    const :result_code, T.nilable(String), name: "resultCode"
    const :result_message, T.nilable(String), name: "resultMessage"
    const :transaction_id, T.nilable(String), name: "transactionId"
    const :gateway_order_id, T.nilable(String), name: "gatewayOrderId"

    # Fields only present when success is false
    const :reasons, T::Array[T::Hash[String, String]], default: []
    const :request_id, T.nilable(String), name: "requestId"
    const :process_id, T.nilable(String), name: "processId"
    const :payment_gateway_response, T.nilable(T::Hash[String, T.untyped]), name: "paymentGatewayResponse"

    sig { returns(T::Boolean) }
    def card_error?
      !success && parsed_processor_response_code == "402"
    end

    sig { returns(T::Boolean) }
    def success?
      result_code == "0"
    end

    sig { returns(String) }
    def parsed_processor_response_code
      if success
        result_code
      else
        parsed_errors["gatewayErrorCode"]
      end
    end

    sig { returns(String) }
    def parsed_processor_response_message
      if success
        result_message
      else
        parsed_errors["gatewayErrorMessage"]
      end
    end

    sig { returns(T.nilable(Integer)) }
    def parsed_error_code
      parsed_errors["code"]
    end

    private

    sig do
      returns({
        "code" => T.nilable(Integer),
        "gatewayErrorCode" => T.nilable(String),
        "gatewayErrorMessage" => T.nilable(String)
      })
    end
    memoize def parsed_errors
      if success
        return { "code" => nil, "gatewayErrorCode" => nil, "gatewayErrorMessage" => nil }
      end
      # Zuora returns errors in a reasons array that looks like this
      # [{"code": 123456, "message": "gatewayErrorCode=DECLINE, gatewayErrorMessage=Declined"}]
      reason = T.must(reasons.first)
      parsed_error_message = Hash[
        T.must(reason["message"]).split(", ").map do |pair|
          k, v = pair.split("=", 2)
          [k, v]
        end
      ]

      {
        "code" => parsed_error_message["code"]&.to_i,
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

    CreateResponse.from_hash(response)
  end
end
