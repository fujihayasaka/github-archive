# typed: strict
# frozen_string_literal: true

module Billing
  class ZuoraRefund
    include GitHub::Memoizer

    sig do
      params(
        sale_transaction: Billing::BillingTransaction,
        refund_amount: Billing::Money,
        refund_invoice_payment_data: T.nilable(T::Hash[String, Billing::Money]),
        external_refund_reference_id: T.nilable(String)
      ).returns(GitHub::Billing::Result)
    end
    def self.process(sale_transaction, refund_amount, refund_invoice_payment_data = nil, external_refund_reference_id: nil)
      new(sale_transaction, refund_amount, refund_invoice_payment_data, external_refund_reference_id:).process
    end

    sig { returns(Billing::Money) }
    attr_reader :refund_amount
    sig { returns(Billing::BillingTransaction) }
    attr_reader :sale_transaction
    sig { returns(T::Hash[String, T.untyped]) }
    attr_reader :zuora_response
    sig { returns(T.nilable(T::Hash[String, Billing::Money])) }
    attr_reader :refund_invoice_payment_data
    sig { returns(T.nilable(String)) }
    attr_reader :external_refund_reference_id

    delegate :platform_transaction_id, to: :sale_transaction

    sig do
      params(
        sale_transaction: Billing::BillingTransaction,
        refund_amount: Billing::Money,
        refund_invoice_payment_data: T.nilable(T::Hash[String, Billing::Money]),
        external_refund_reference_id: T.nilable(String)
      ).void
    end
    def initialize(sale_transaction, refund_amount, refund_invoice_payment_data = nil, external_refund_reference_id: nil)
      @refund_amount = refund_amount
      @sale_transaction = sale_transaction
      @refund_invoice_payment_data = refund_invoice_payment_data
      @zuora_response = T.let({}, T::Hash[String, T.untyped])
      @external_refund_reference_id = T.let(external_refund_reference_id, T.nilable(String))
    end

    sig { returns(GitHub::Billing::Result) }
    def process
      GitHub.dogstats.time("zuora.timing.transaction_refund") { generate_refund }
    rescue Zuorest::HttpError => e
      Failbot.report!(e, app: "github-zuora")
      GitHub::Billing::Result.failure("Error:: #{e.message}")
    end

    private

    sig { returns(GitHub::Billing::Result) }
    def generate_refund
      begin
        refund_params = {
          Amount: refund_amount.dollars,
          PaymentId: platform_transaction_id,
          SourceType: "Payment",
          Type: "Electronic",
          RefundInvoicePaymentData: build_refund_invoice_payment_data
        }.compact

        if is_external_refund?
          method_type = sale_transaction.payment_type.split("_").map(&:capitalize).join
          refund_params.merge!(
            Type: "External",
            MethodType: sale_transaction.no_charge? ? "Other" : method_type,
            RefundDate: GitHub::Billing.today.iso8601,
          )
        end

        @zuora_response = GitHub.zuorest_client.create_refund refund_params
        response = GitHub::Billing::Result.from_zuora zuora_response
      rescue Faraday::TimeoutError
        zero_out_refund if zuora_payment.refund_amount.to_f > 0
        raise
      end

      return unrefundable_error if response.failed? || refund_failed?
      if response.success?
        refund_transaction = log_refund if !sale_transaction.live_user.present? || is_external_refund?
        response.billing_transaction = refund_transaction
        zero_out_refund
      end
      response
    end

    sig { returns(T.nilable(T::Hash[Symbol, T::Array[T::Hash[Symbol, T.untyped]]])) }
    def build_refund_invoice_payment_data
      refund_invoice_payment_data = self.refund_invoice_payment_data
      return if refund_invoice_payment_data.blank?

      invoice_refunds = refund_invoice_payment_data.map do |invoice_id, refund_amount|
        { InvoiceId: invoice_id, RefundAmount: refund_amount.dollars }
      end

      { RefundInvoicePayment: invoice_refunds }
    end

    sig { returns(Billing::BillingTransaction) }
    def log_refund
      GitHub.dogstats.increment("billing.refund")

      refund_transaction = sale_transaction.build_refund_transaction(
        amount_in_cents: refund_amount.cents,
        platform_transaction_id: zuora_refund_id,
        refund_reference_id: is_external_refund? ? external_refund_reference_id : zuora_refund["ReferenceID"]
      )

      refund_transaction.save

      refund_transaction
    end

    sig { returns(GitHub::Billing::Result) }
    def zero_out_refund
      ::Billing::Zuora::ZeroOutInvoices.for_transaction(platform_transaction_id)
    end

    sig { returns(T.nilable(String)) }
    def zuora_refund_id
      zuora_response["Id"]
    end

    sig { returns(GitHub::Billing::Result) }
    def unrefundable_error
      GitHub::Billing::Result.failure "Cannot refund a transaction unless it is settled."
    end

    sig { returns(T::Boolean) }
    def is_external_refund?
      external_refund_reference_id.present?
    end

    sig { returns(T::Boolean) }
    def refund_failed?
      zuora_refund["Status"] == "Error"
    end

    sig { returns(Billing::Zuora::Payment) }
    memoize def zuora_payment
      Billing::Zuora::Payment.find(platform_transaction_id)
    end

    sig { returns(T::Hash[String, T.untyped]) }
    memoize def zuora_refund
      GitHub.zuorest_client.get_refund zuora_refund_id
    end
  end
end
