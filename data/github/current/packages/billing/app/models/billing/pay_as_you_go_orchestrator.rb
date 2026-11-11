# typed: strict
# frozen_string_literal: true

module Billing
  class PayAsYouGoOrchestrator
    include GitHub::Memoizer

    sig do
      params(
        customer: Customer,
        amount_to_pay: Billing::Money,
        product_uuid: Billing::ProductUUID,
        idempotency_key: T.nilable(String),
      ).void
    end
    def initialize(customer:, amount_to_pay:, product_uuid:, idempotency_key: nil)
      @customer = customer
      @product_uuid = product_uuid
      @amount_to_pay = amount_to_pay
      @idempotency_key_override = idempotency_key
    end

    # The idempotency key identifying this advance payment. Callers stash this after a declined
    # India RBI charge and pass it back on the manual-payment finalization re-POST so the retry
    # reuses the same pending invoice (emitting the charge-collected event) instead of creating —
    # and charging — a second invoice.
    sig { returns(String) }
    memoize def idempotency_key
      @idempotency_key_override || default_idempotency_key
    end

    sig { returns(GitHub::Result) }
    def call
      return GitHub::Result.error("ProductUUID must be metered") unless @product_uuid.metered?
      product_rate_plan_charge_id = @product_uuid.zuora_product_rate_plan_charge_ids.values.first

      key = idempotency_key

      advance_payment = Billing::AdvancePayment.new(
        customer: @customer,
        idempotency_key: key,
      )

      advance_payment_result = advance_payment.collect!(
        items: [
          Billing::Zuora::StandaloneInvoiceItem.new(
            product_rate_plan_charge_id: product_rate_plan_charge_id,
            quantity: @amount_to_pay.dollars.to_f,
            amount_in_cents: @amount_to_pay.cents,
            service_end_date: GitHub::Billing.today,
          ),
        ],
        comment: "Pay-as-you-go charge for product #{@product_uuid.name}",
        origin: "Pay-as-you-go orchestrator",
      )

      result = if advance_payment_result.success?
        GlobalInstrumenter.instrument("billing.pay_as_you_go_charge_collected", {
          customer_id: @customer.id,
          amount_in_cents: @amount_to_pay.cents,
          payment_processor_transaction_id: advance_payment.payment_id,
          product_key: @product_uuid.product_key,
          product_type: @product_uuid.product_type,
          applied_at: Time.now.utc.to_i,
        })
        GitHub::Result.new { advance_payment.payment_id }
      elsif advance_payment_result.declined?
        manual_payment_required_result(advance_payment) ||
          GitHub::Result.error("Your payment was declined, please update your payment method and try again.")
      else
        GitHub::Result.error("We couldn't process your payment. Please try again.")
      end

      GitHub.logger.info(logger_fields.merge(
        "code.function" => "call",
        "gh.billing.pay_as_you_go.success" => advance_payment_result.success?,
        "gh.billing.pay_as_you_go.product_rate_plan_charge_id" => product_rate_plan_charge_id,
        "gh.billing.pay_as_you_go.idempotency_key" => key,
        "gh.billing.zuora.payment.id" => advance_payment_result.payment&.id,
        "gh.billing.pay_as_you_go.error" => advance_payment_result.success? ? nil : advance_payment_result.error_message,
      ).compact)

      result
    rescue Zuorest::HttpError => e
      GitHub.logger.error(logger_fields.merge(
        "code.function" => "call",
        "exception" => e,
        "gh.billing.pay_as_you_go.error" => e.message,
      ))
      GitHub.dogstats.increment("billing.pay_as_you_go.zuora_error", tags: [
        "product_key:#{@product_uuid.product_key}",
      ])
      GitHub::Result.error("A payment processing error occurred, please try again.")
    end

    private

    # When a declined pay-as-you-go charge belongs to a customer that must complete payments manually
    # (e.g. India RBI), disable auto-pay (if not already) and surface the pending standalone invoice as
    # a Billing::ManualPaymentRequiredError so the caller can redirect them to the manual payments page
    # to authorize it. Mirrors Billing::SubscriptionItemUpdater#collect_advance_payment. Returns nil
    # (so the caller falls back to the normal declined message) when manual payment doesn't apply.
    sig { params(advance_payment: Billing::AdvancePayment).returns(T.nilable(GitHub::Result)) }
    def manual_payment_required_result(advance_payment)
      return nil unless @customer.requires_manual_transactions?

      owner = @customer.billable_owner
      return nil if owner.nil?
      return nil unless FeatureFlag.vexi.enabled?(:copilot_rbi_manual_payment_signup, owner, default: false)

      owner.disable_auto_pay!(:india_rbi) unless @customer.autopay_disabled_by_india_rbi?
      GitHub::Result.error(Billing::ManualPaymentRequiredError.new(invoice_id: advance_payment.pending_invoice_id))
    end

    # The default idempotency key when the caller doesn't supply one: scoped to the product rate plan
    # charge and the count of recent line items, so each distinct usage payment gets its own key.
    sig { returns(String) }
    def default_idempotency_key
      product_rate_plan_charge_id = @product_uuid.zuora_product_rate_plan_charge_ids.values.first
      relevant_line_item_count = Billing::BillingTransaction::LineItem
        .for_customer(@customer.id)
        .for_zuora_product_rate_plan_charge_id(product_rate_plan_charge_id)
        .created_at_or_after(1.month.ago)
        .count
      "#{product_rate_plan_charge_id}-#{relevant_line_item_count}"
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def logger_fields
      {
        "code.namespace" => self.class.name,
        "gh.billing.customer.id" => @customer.id,
        "gh.billing.customer.zuora_account_id" => @customer.zuora_account_id,
        "gh.billing.pay_as_you_go.amount_in_cents" => @amount_to_pay.cents,
        "gh.billing.pay_as_you_go.product_key" => @product_uuid.product_key,
        "gh.billing.pay_as_you_go.product_type" => @product_uuid.product_type,
      }
    end
  end
end
