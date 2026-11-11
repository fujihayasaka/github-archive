# typed: strict
# frozen_string_literal: true

module Billing
  # An advance payment is a payment for one or more product rate plan charges that are
  # expected to be included in an upcoming invoice for the customer's subscription.
  #
  # This class encapsulates all required logic for generating an invoice for one or more
  # product rate plan charges, collecting payment for the invoice, and maintaining state
  # throughout the entire process. This class intentionally does NOT include any retry
  # logic to allow this class to be used in synchronous contexts and to allow callers to
  # abort the process at any point.
  #
  # The advance payment lifecycle is as follows:
  #
  #   not started → pending invoice → collected payment (or → cleaned up)
  #
  # Each advance payment is uniquely identified using a combination of the customer ID and
  # the provided idempotency key. The state of an advance payment is stored for a limited
  # period of time as defined by the PENDING_INVOICE_TTL and COLLECTED_PAYMENT_TTL constants.
  class AdvancePayment
    # The length of time we keep a record of a pending invoice.
    # Invoices that haven't been paid within this window are zeroed out to avoid orphaned invoices.
    PENDING_INVOICE_TTL = T.let(1.day, ActiveSupport::Duration)
    # The length of time we keep a record of a collected payment.
    # Reconciliation must occur within this window or the customer can be double-charged.
    COLLECTED_PAYMENT_TTL = T.let(1.week, ActiveSupport::Duration)

    class CollectedPayment < T::Struct
      const :payment_id, String
      const :invoice_id, String
      const :invoice_items, T::Array[::Billing::Zuora::InvoiceItem]
    end

    class CollectionResult < T::Struct
      const :invoice, T.nilable(::Billing::Zuora::Invoice), default: nil
      const :payment, T.nilable(::Billing::Zuora::Payment), default: nil
      const :error_message, T.nilable(String), default: nil

      sig { returns(T::Boolean) }
      def success?
        error_message.nil?
      end

      sig { returns(T::Boolean) }
      def failed?
        !success?
      end

      sig { returns(T::Boolean) }
      def declined?
        return false unless payment
        response = T.must(payment).gateway_response.to_s
        return true if response.match?(/declined/i)
        return true if response.match?(/The transaction did not complete with the customer'?s selected payment method/i)
        false
      end
    end

    sig { params(customer: ::Customer, idempotency_key: String).void }
    def initialize(customer:, idempotency_key:)
      @customer = customer
      @idempotency_key = idempotency_key
    end

    sig { returns(T.nilable(String)) }
    def payment_id
      json = ::Billing::Kv.store.get(collected_payment_key).value! { nil }
      return nil unless json
      JSON.parse(json).fetch("payment_id")
    end

    sig { returns(T::Boolean) }
    def collected?
      payment_id.present?
    end

    # The id of the pending advance-payment standalone invoice awaiting collection.
    # Once the payment settles the pending invoice is cleared (see #mark_settled), so this returns nil.
    sig { returns(T.nilable(String)) }
    def pending_invoice_id
      ::Billing::Kv.store.get(pending_invoice_key).value! { nil }
    end

    sig do
      params(
        items: T::Array[::Billing::Zuora::StandaloneInvoiceItem],
        comment: String,
        origin: String,
      ).returns(CollectionResult)
    end
    def collect!(items:, comment:, origin:)
      if (existing_payment_id = payment_id)
        return CollectionResult.new(payment: ::Billing::Zuora::Payment.find(existing_payment_id))
      end
      return CollectionResult.new(error_message: "A valid payment method is required") unless @customer.payment_method&.valid_payment_token?
      return CollectionResult.new(error_message: "At least one item is required") if items.empty?
      return CollectionResult.new unless positive_balance_invoice?(items)

      invoice = find_or_create_invoice(items: items)
      return CollectionResult.new(error_message: "Failed to create invoice") unless invoice

      payment = find_or_collect_payment(invoice: invoice, comment: comment, origin: origin)
      unless payment.status == "Processed"
        log("Advance payment collection failed", invoice: invoice, payment: payment, origin: origin)
        return CollectionResult.new(invoice: invoice, payment: payment, error_message: payment.gateway_response || "Payment failed")
      end

      record_payment(payment: payment, invoice: invoice)
      log("Advance payment collected", invoice: invoice, payment: payment, origin: origin)
      CollectionResult.new(invoice: invoice, payment: payment)
    rescue Zuorest::HttpError => e
      GitHub.logger.error(logger_fields(invoice: invoice, origin: origin).merge(exception: e))
      raise
    end

    # Deprecated in favour of cancel_pending_invoice!
    sig { void }
    def cleanup_orphaned_invoice!
      return unless invoice_id = pending_invoice_id
      invoice = ::Billing::Zuora::Invoice.new(invoice_id)
      ::Billing::Zuora::ZeroOutInvoice.run(invoice: invoice) if invoice.balance.positive?
      clear_pending_invoice
    end

    sig { params(customer: ::Customer).returns(T::Array[CollectedPayment]) }
    def self.collected_payments(customer:)
      records = ::Billing::Kv.store.mget_prefix(collected_payment_key_prefix(customer.id)).value!
      records.values.map do |json|
        record = JSON.parse(json)
        invoice_items = record.fetch("items").map { |item| ::Billing::Zuora::InvoiceItem.new(item) }
        CollectedPayment.new(
          payment_id: record.fetch("payment_id"),
          invoice_id: record.fetch("invoice_id"),
          invoice_items: invoice_items,
        )
      end
    end

    sig { params(customer: ::Customer).returns(T::Array[String]) }
    def self.pending_invoice_ids(customer:)
      ::Billing::Kv.store.mget_prefix(pending_invoice_key_prefix(customer.id)).value!.values
    end

    sig { params(customer: ::Customer, invoice_id: String).returns(T::Boolean) }
    def self.cancel_pending_invoice!(customer:, invoice_id:)
      pending_invoice_records = ::Billing::Kv.store.mget_prefix(pending_invoice_key_prefix(customer.id)).value!
      pending_invoice_key = pending_invoice_records.key(invoice_id)
      return false if pending_invoice_key.nil?

      invoice = ::Billing::Zuora::Invoice.new(invoice_id)
      ::Billing::Zuora::ZeroOutInvoice.run(invoice: invoice) if invoice.balance.positive?
      ::Billing::Kv.store.del(pending_invoice_key)
      true
    end

    private

    sig { params(items: T::Array[::Billing::Zuora::StandaloneInvoiceItem]).returns(T::Boolean) }
    def positive_balance_invoice?(items)
      balance = items.sum do |item|
        discounts = item.discount_items.sum { |d| d.amount_in_cents.abs }
        item.amount_in_cents - discounts
      end
      balance.positive?
    end

    sig { params(items: T::Array[::Billing::Zuora::StandaloneInvoiceItem]).returns(T.nilable(::Billing::Zuora::Invoice)) }
    def find_or_create_invoice(items:)
      if (existing_id = pending_invoice_id)
        return ::Billing::Zuora::Invoice.new(existing_id)
      end

      invoice = ::Billing::Zuora::Invoice.create_standalone(zuora_account_id: @customer.zuora_account_id,
        items: items, auto_pay: false, idempotency_key: zuora_idempotency_key)
      return nil unless invoice

      record_pending_invoice(invoice.id)

      ::Billing::ZeroOutAdvancePaymentInvoiceJob
        .set(wait: PENDING_INVOICE_TTL)
        .perform_later(customer_id: @customer.id, invoice_id: invoice.id)

      invoice
    end

    sig { params(invoice: ::Billing::Zuora::Invoice, comment: String, origin: String).returns(::Billing::Zuora::Payment) }
    def find_or_collect_payment(invoice:, comment:, origin:)
      existing_payments = ::Billing::Zuora::Payment.find_for_invoice(invoice.id)
      existing_payments.find { |p| p.status == "Processed" } || collect_payment(invoice: invoice, comment: comment, origin: origin)
    end

    sig { params(invoice: ::Billing::Zuora::Invoice, comment: String, origin: String).returns(::Billing::Zuora::Payment) }
    def collect_payment(invoice:, comment:, origin:)
      payment_method = T.must(@customer.payment_method)
      payment_token = payment_method.payment_token
      gateway_type = payment_method.credit_card? ? :credit_card : :paypal

      billable_owner = @customer.billable_owner
      payment_gateway = ::Billing::Zuora::PaymentGateway.for(billable_owner, type: gateway_type)

      ::Billing::Zuora::Payment.create(
        origin: origin,
        customer: @customer,
        comment: comment,
        payment_token: payment_token,
        invoices: [invoice],
        payment_gateway: payment_gateway,
      )
    end

    sig { params(payment: ::Billing::Zuora::Payment, invoice: ::Billing::Zuora::Invoice).void }
    def record_payment(payment:, invoice:)
      collected_payment = {
        "payment_id" => payment.id,
        "invoice_id" => invoice.id,
        "items" => invoice.invoice_items.map { |item| item.to_h.compact },
      }
      ::Billing::Kv.store.set(collected_payment_key, collected_payment.to_json, expires: COLLECTED_PAYMENT_TTL.from_now)
      clear_pending_invoice
    end

    sig { params(invoice_id: String).void }
    def record_pending_invoice(invoice_id)
      ::Billing::Kv.store.set(pending_invoice_key, invoice_id)
    end

    sig { void }
    def clear_pending_invoice
      ::Billing::Kv.store.del(pending_invoice_key)
    end

    sig { returns(String) }
    def pending_invoice_key
      "#{self.class.send(:pending_invoice_key_prefix, @customer.id)}#{@idempotency_key}"
    end

    sig { returns(String) }
    def collected_payment_key
      "#{self.class.send(:collected_payment_key_prefix, @customer.id)}#{@idempotency_key}"
    end

    sig { returns(String) }
    def zuora_idempotency_key
      "#{@customer.id}.#{@idempotency_key}"
    end

    sig { params(customer_id: Integer).returns(String) }
    def self.key_prefix(customer_id)
      "billing.customer.#{customer_id}.advance_payment."
    end
    private_class_method :key_prefix

    sig { params(customer_id: Integer).returns(String) }
    def self.pending_invoice_key_prefix(customer_id)
      "#{key_prefix(customer_id)}pending_invoice."
    end
    private_class_method :pending_invoice_key_prefix

    sig { params(customer_id: Integer).returns(String) }
    def self.collected_payment_key_prefix(customer_id)
      "#{key_prefix(customer_id)}collected_payment."
    end
    private_class_method :collected_payment_key_prefix

    sig { params(message: String, invoice: T.nilable(::Billing::Zuora::Invoice), origin: String, payment: T.nilable(::Billing::Zuora::Payment)).void }
    def log(message, invoice:, origin:, payment: nil)
      GitHub.logger.info(message, logger_fields(invoice: invoice, origin: origin).merge(
        "gh.billing.zuora.payment.id" => payment&.id,
      ))
    end

    sig { params(invoice: T.nilable(::Billing::Zuora::Invoice), origin: String).returns(T::Hash[String, T.untyped]) }
    def logger_fields(invoice:, origin:)
      {
        "code.namespace" => self.class.name,
        "gh.billing.advance_payment.idempotency_key" => @idempotency_key,
        "gh.billing.advance_payment.origin" => origin,
        "gh.billing.customer.id" => @customer.id,
        "gh.billing.customer.zuora_account_id" => @customer.zuora_account_id,
        "gh.billing.invoice.id" => invoice&.id,
      }
    end
  end
end
