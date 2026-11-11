# typed: true
# frozen_string_literal: true

class HydroSalesforceSelfServeEligibleJob < HydroMessageJob
  class UnknownRecordError < StandardError; end

  queue_as :hydro_salesforce_self_serve_eligible
  retry_on_dirty_exit
  # Roughly 3 days of retries
  retry_on(UnknownRecordError, delay: :polynomially_longer, max_retries: 25) do |_, error|
    GitHub.logger.error("Retry exhausted", exception: error)
  end

  # Public: process a Hydro message
  sig { void }
  def perform
    zuora_account_id = message[:zuora_account_id]
    previous_eligible = message[:previous_eligible]
    current_eligible = message[:current_eligible]

    customers = Customer.with_zuora_account_id(zuora_account_id)
    if customers.size != 1
      raise UnknownRecordError, "Expected 1 customer with Zuora Account ID #{zuora_account_id}, but found #{customers.size}"
    end

    sales_serve_plan_subscription = customers.first&.sales_serve_plan_subscription
    if sales_serve_plan_subscription.nil?
      raise UnknownRecordError, "Sales serve plan subscription not found for customer with Zuora Account ID #{zuora_account_id}"
    end

    GitHub.context.push(actor: User.staff_user)

    with_write do
      sales_serve_plan_subscription.update!(self_serve_eligible: current_eligible)
    end
  end
end
