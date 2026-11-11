# typed: strict
# frozen_string_literal: true

module Billing
  class EnableAutoPayAfterCardSetupJob < BillingJob
    queue_as :billing

    discard_on ActiveJob::DeserializationError
    retry_on_dirty_exit

    sig { params(customer_id: Integer, payment_id: String).void }
    def perform(customer_id, payment_id)
      log_context = {
        "code.namespace": "Billing::EnableAutoPayAfterCardSetupJob",
        "code.function": "perform",
        "gh.billing.customer.id": customer_id,
        "gh.billing.zuora.payment.id": payment_id,
      }

      customer = Customer.find_by(id: customer_id)
      if customer.nil?
        GitHub.logger.warn("EnableAutoPayAfterCardSetup: customer not found", log_context)
        return
      end

      account = customer.billable_owner
      return unless account&.autopay_disabled_by_india_rbi?

      unless customer.zuora?
        GitHub.logger.warn("EnableAutoPayAfterCardSetup: customer is not on Zuora", log_context)
        return
      end

      payment_method_id = fetch_payment_method_id(payment_id)
      unless payment_method_id
        GitHub.logger.warn("EnableAutoPayAfterCardSetup: payment method ID not found", log_context)
        return
      end

      zuora_account = T.must(customer.zuora_account)
      response = zuora_account.update!(DefaultPaymentMethodId: payment_method_id)
      result = GitHub::Billing::Result.from_zuora(response.first)
      unless result.success?
        Failbot.report("EnableAutoPayAfterCardSetup: failed to set default payment method",
          "code.namespace" => "Billing::EnableAutoPayAfterCardSetupJob",
          "code.function" => "perform",
          "gh.billing.customer.id" => customer_id.to_s,
          "gh.billing.zuora.payment.id" => payment_id,
          "gh.billing.zuora.payment_method.id" => payment_method_id,
          "gh.billing.zuora.response.error_message" => result.message,
        )
        return
      end

      zuora_pm = Billing::Zuora::PaymentMethod.find(payment_method_id)

      with_write do
        update_local_payment_method(customer, payment_method_id, zuora_pm)
        account.enable_auto_pay!(:india_rbi)
      end
    end

    private

    sig { params(payment_id: String).returns(T.nilable(String)) }
    def fetch_payment_method_id(payment_id)
      payment = GitHub.zuorest_client.get_payment(payment_id)
      pm_id = payment&.dig("PaymentMethodId")
      pm_id.present? ? pm_id : nil
    end

    sig { params(customer: Customer, payment_method_id: String, zuora_pm: T.nilable(Billing::Zuora::PaymentMethod)).void }
    def update_local_payment_method(customer, payment_method_id, zuora_pm)
      local_pm = customer.payment_method
      return unless local_pm
      return unless zuora_pm

      local_pm.payment_token = payment_method_id
      local_pm.assign_from_zuora_payment_method(zuora_pm)
      local_pm.save!
    end
  end
end
