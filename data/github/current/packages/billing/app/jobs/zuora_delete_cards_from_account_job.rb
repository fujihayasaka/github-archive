# typed: strict
# frozen_string_literal: true

class ZuoraDeleteCardsFromAccountJob < BillingJob
  include GitHub::Billing::ZuoraRateLimitHandler

  queue_as :zuora

  retry_on_dirty_exit

  ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer) do |_job, error|
      Failbot.report(error)
    end
  end

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, ZuoraDeleteCardsFromAccountJob)

    zuora_rate_limit_handler(self, error)
  end

  sig { params(zuora_account_id: String).void }
  def perform(zuora_account_id)
    Failbot.push("gh.billing.zuora.account.id" => zuora_account_id)

    set_default_payment_method_to_null(zuora_account_id)

    Zuorest::Model::PaymentMethod.find_by_account_id(zuora_account_id).each do |payment_method|
      payment_method.delete
    end
  end

  private

  sig { params(zuora_account_id: String).returns(T::Array[T::Hash[String, T.untyped]]) }
  def set_default_payment_method_to_null(zuora_account_id)
    # https://www.zuora.com/developer/api-reference/#operation/Action_POSTupdate
    GitHub.zuorest_client.update_action(
      {
        "objects": [{
          "AutoPay": false,
          "fieldsToNull": ["DefaultPaymentMethodId"],
          "Id": zuora_account_id,
        }],
        "type": "Account",
      },
    )
  end
end
