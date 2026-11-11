# typed: strict
# frozen_string_literal: true

# Common methods for Hydro instrumentation in Zuora webhooks
module Billing::Zuora::Webhooks::HydroInstrumentation
  extend T::Helpers

  requires_ancestor { ::Billing::Zuora::Webhooks::WebhookHandler }

  # Internal: Instrument the payment transaction so that it can be logged
  # in Hydro to github_billing_v0_payment_transaction, and adds an audit log for easier
  # support debugging.
  #
  # success - Whether or not this transaction was successful
  # trial_completion_status_before_processing - business.trial_completion_status before the job has run
  # trial_completion_status_after_processing - business.trial_completion_status after the job has run
  # product_type - The product type of the current/new subscription item's subscribable
  # product_key - The product key of the current/new subscription item's subscribable
  # previous_product_type - The product type of the previous subscription item's subscribable
  # previous_product_key - The product key of the previous subscription item's subscribable
  sig do
    params(
      success: T::Boolean,
      trial_completion_status_before_processing: T.nilable(String),
      trial_completion_status_after_processing: T.nilable(String),
      product_type: T.nilable(String),
      product_key: T.nilable(String),
      previous_product_type: T.nilable(String),
      previous_product_key: T.nilable(String)
    ).void
  end
  def instrument_payment_transaction(success:, trial_completion_status_before_processing: nil, trial_completion_status_after_processing: nil, product_type: nil, product_key: nil, previous_product_type: nil, previous_product_key: nil)
    account = self.account

    payment_information = {
      payment_method_id: payment_method&.id,
      payment_amount: zuora_payment.amount_in_cents,
      attempt_number: zuora_payment.num_consecutive_failures + 1,
      processor_response_code: zuora_payment.processor_response_code,
      processor_response: zuora_payment.processor_response,
    }

    product_information = {
      product_type: product_type,
      product_key: product_key,
      previous_product_type: previous_product_type,
      previous_product_key: previous_product_key,
    }

    payload = {
      user_id: account.is_a?(::User) ? account.id : nil,
      business_id: account.is_a?(::Business) ? account.id : nil,
      success: success,
    }.merge(payment_information).merge(product_information)
    # hydro github_billing_v0_payment_transaction
    GlobalInstrumenter.instrument("billing.payment_transaction", payload)

    # Audit Logs
    audit_log_payload = {}
    if account.is_a?(::User)
      audit_log_payload = payment_information.merge(product_information).merge({
        user_id: account.id,
        user: account.display_login
      })
    end
    if account.is_a?(::Business)
      audit_log_payload = payment_information.merge(product_information).merge({
        business_id: account.id,
        business: account.display_login,
        trial_completion_status_before_processing: trial_completion_status_before_processing,
        trial_completion_status_after_processing: trial_completion_status_after_processing,
      })
    end
    event = success ? "billing.payment_processed" : "billing.payment_declined"
    GitHub.instrument event, audit_log_payload
  end

  # Internal: Extract product type and key information from the payment's invoice items.
  #
  # Matches invoice items against ProductUUID records by product name and
  # productRatePlanChargeId.
  #
  # Credit items (negative charge_amount) represent the previous subscription,
  # charge items (positive/zero charge_amount) represent the current subscription.
  sig { returns(T::Hash[Symbol, T.nilable(String)]) }
  def payment_product_info
    invoice_items = zuora_payment.invoice_items

    matched_items = invoice_items.filter_map do |item|
      next if item.charge_amount.zero?
      product = find_product_for_invoice_item(item)
      [product, item] if product
    end

    credit_match = matched_items.detect { |_product, item| item.charge_amount.negative? }
    charge_match = matched_items.detect { |_product, item| !item.charge_amount.negative? }

    {
      product_type: charge_match&.first&.product_type,
      product_key: charge_match&.first&.product_key,
      previous_product_type: credit_match&.first&.product_type,
      previous_product_key: credit_match&.first&.product_key,
    }
  end

  private

  # Internal: Find the ProductUUID matching an invoice item by narrowing candidates
  # using the invoice item's product_name, then confirming via charge ID match.
  sig { params(invoice_item: Billing::Zuora::InvoiceItem).returns(T.nilable(Billing::ProductUUID)) }
  def find_product_for_invoice_item(invoice_item)
    product_name = invoice_item.product_name
    return nil if product_name.blank?

    # This currently only works for Copilot products
    # Note that the ProductUUID name is not guaranteed to exist for other ProductUUIDs
    Billing::ProductUUID.copilot
      .where(name: product_name, metered: false)
      .detect { |p| p.matches_invoice_item?(invoice_item) }
  end
end
