# typed: strict
# frozen_string_literal: true

module Billing
  module Zuora
    class ZeroOutInvoices
      SUBSCRIPTION_TYPE = "subscription"
      TRANSACTION_TYPE  = "transaction"
      ACCOUNT_TYPE = "account"

      # Public: creates a new instance of ZeroOutInvoices
      #
      # This should really only be used when called from .for_transaction or
      # .for_subscription to ensure you get the correct invoices and "belongs_to" values
      #
      # invoices: the invoices we plan to zero out the balance of
      # invoice_belongs_to_type: String representing the related object.
      # invoice_belongs_to_id: String id for the belongs_to_type record in Zuora
      #
      # Returns an instance of ::Billing::Zuora::ZeroOutInvoices
      sig do
        params(
          invoices: T::Array[::Billing::Zuora::Invoice],
          invoice_belongs_to_type: String,
          invoice_belongs_to_id: String,
        ).void
      end
      def initialize(invoices:, invoice_belongs_to_type:, invoice_belongs_to_id:)
        @invoices                = invoices
        @invoice_belongs_to_type = invoice_belongs_to_type
        @invoice_belongs_to_id   = invoice_belongs_to_id

        @restraint = T.let(GitHub::Restraint.new, GitHub::Restraint)
      end

      # Public: Zeroes out the balance of an invoice for a given Payment and refund amount
      #
      # zuora_transaction_id: The ID of the Zuora Payment
      # fetcher: class used to get invoices from Zuora
      #
      # Raises ::Billing::Zuora::ZeroOutError if at least one invoice does not zero out
      sig do
        params(
          zuora_transaction_id: String,
          fetcher: T.untyped
        ).returns(::GitHub::Billing::Result)
      end
      def self.for_transaction(zuora_transaction_id, fetcher: ::Billing::Zuora::Invoice)
        new(
          invoices: fetcher.invoices_for_transaction(zuora_transaction_id),
          invoice_belongs_to_type: TRANSACTION_TYPE,
          invoice_belongs_to_id: zuora_transaction_id,
        ).zero_out
      end

      # Public: Zeroes out the balance of an invoice for a given subscription
      #
      # zuora_subscription_number: The number of the Zuora Subscription
      # fetcher: class used to get invoices from Zuora
      #
      # Raises ::Billing::Zuora::ZeroOutError if at least one invoice does not zero out
      sig do
        params(
          zuora_subscription_number: String,
          fetcher: T.untyped
        ).returns(::GitHub::Billing::Result)
      end
      def self.for_subscription(zuora_subscription_number, fetcher: ::Billing::Zuora::Invoice)
        new(
          invoices: fetcher.invoices_for_subscription(zuora_subscription_number),
          invoice_belongs_to_type: SUBSCRIPTION_TYPE,
          invoice_belongs_to_id: zuora_subscription_number,
        ).zero_out
      end

      # Public: Zeroes out the balance of invoices for a given account
      #
      # zuora_account_id: The number of the Zuora Subscription
      # fetcher: class used to get invoices from Zuora
      #
      # Raises ::Billing::Zuora::ZeroOutError if at least one invoice does not zero out
      sig do
        params(
          zuora_account_id: String,
          fetcher: T.untyped
        ).returns(::GitHub::Billing::Result)
      end
      def self.for_account(zuora_account_id, fetcher: ::Billing::Zuora::Invoice)
        new(
          invoices: fetcher.invoices_for_account(zuora_account_id),
          invoice_belongs_to_type: ACCOUNT_TYPE,
          invoice_belongs_to_id: zuora_account_id,
        ).zero_out
      end

      # Public: Sends a message to each invoice to zero out on Zuora
      #
      # While iterating, it will effectively skip any invoices that are cancelled,
      # as adjustments cannot be created for them, and it causes an error, which
      # then erroneously raises a ZeroOutError
      #
      # Raises ::Billing::Zuora::ZeroOutError if at least one invoice does not zero out
      sig { returns(::GitHub::Billing::Result) }
      def zero_out
        return ::GitHub::Billing::Result.success if invoices.empty?

        results = invoices.map do |invoice|
          if invoice.invoice_id.nil? || invoice.cancelled?
            ::GitHub::Billing::Result.success
          else
            result = zero_out_on_zuora(invoice)
            result[:result]
          end
        end

        process_results(results)
      end

      private

      sig { returns(T::Array[::Billing::Zuora::Invoice]) }
      attr_reader :invoices
      sig { returns(String) }
      attr_reader :invoice_belongs_to_type
      sig { returns(String) }
      attr_reader :invoice_belongs_to_id
      sig { returns(GitHub::Restraint) }
      attr_reader :restraint

      sig do
        type_parameters(:R)
          .params(invoice: ::Billing::Zuora::Invoice, block: T.proc.params(arg0: T.untyped).returns(T.type_parameter(:R)))
          .returns(T.type_parameter(:R))
      end
      def lock_invoice(invoice, &block)
        restraint.lock!(invoice.lock_key, _n = 1, _ttl = 1.minute, &block)
      end

      # Internal: Prep the invoice adjustments that will be sent to zuora to zero out
      #
      # invoice            - the invoice we are zero-ing out
      # adjustment_builder - the class we're using to build the adjustments
      sig do
        params(
          invoice: ::Billing::Zuora::Invoice,
          adjustment_builder: T.untyped
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def zero_out_on_zuora(invoice, adjustment_builder: ::Billing::Zuora::InvoiceItemAdjustmentBuilder)
        # Determine the adjustment amount
        # InvoiceItemAdjustmentBuilder expects a positive or negative adjustment amount
        # depending on whether or not the invoice balance should be reduced or increased.
        adjustment_amount = Billing::Money.new(-invoice.balance * 100)

        # Create invoice item adjustments that will zero out the invoice
        Billing::Zuora::Invoice.record_metrics(
          balance_in_cents: invoice.balance * 100,
          calling_class: "zero_out_invoices",
        )
        invoice_item_adjustments = if invoice.balance <= 0
          []
        else
          adjustment_builder.perform(invoice: invoice, adjustment_amount: adjustment_amount)
        end

        GitHub.logger.info(
          "code.namespace" => self.class.name,
          "code.function" => "zero_out_invoices.zero_out_on_zuora",
          "gh.catalog_service" => "github/payment_processing",
          "gh.billing.zuora.invoice.amount" => invoice.amount,
          "gh.billing.zuora.invoice.balance" => invoice.balance,
          "gh.billing.zuora.invoice.id" => invoice.invoice_id,
          "gh.billing.zuora.invoice.number" => invoice.number,
          "gh.billing.zuora.invoice_item_adjustments" => invoice_item_adjustments.to_s
        )
        return default_response(adjustment_amount: adjustment_amount) if invoice_item_adjustments.empty?

        lock_invoice(invoice) do
          return send_zero_out_to_zuora(adjustments: invoice_item_adjustments, adjustment_amount: adjustment_amount)
        end
      rescue GitHub::Restraint::UnableToLock
        adjustment_amount = Billing::Money.new(-invoice.balance * 100)
        default_response(adjustment_amount: adjustment_amount)
      end

      # Internal: send the adjustments to zuora
      # NB: This makes a remote call to Zuora
      #
      # adjustments   - an array of hashes that reflect the necessary changes
      # adjustment_amount - the resulting adjustment_amount
      sig do
        params(
          adjustments: T::Array[T::Hash[Symbol, T.untyped]],
          adjustment_amount: Billing::Money
        ).returns({ result: GitHub::Billing::Result, refund_amount: Billing::Money })
      end
      def send_zero_out_to_zuora(adjustments:, adjustment_amount:)
        response = GitHub.zuorest_client.create_action(objects: adjustments, type: "InvoiceItemAdjustment")

        results = response.map { |r| GitHub::Billing::Result.from_zuora(r) }
        success = results.all?(&:success?)

        GitHub.logger.info(
          "code.namespace" => self.class.name,
          "code.function" => "zero_out_invoices.send_zero_out_to_zuora",
          "gh.catalog_service" => "github/payment_processing",
          "gh.billing.zuora.invoice_item_adjustments" => adjustments.to_s,
          "gh.billing.zuora.response_results" => results.map(&:to_s).to_s,
        )

        GitHub.dogstats.increment("zuora.invoices.zero_out", tags: ["success:#{success}", "class:zero_out_invoices"])

        result = if success
          GitHub::Billing::Result.success
        else
          GitHub::Billing::Result.failure(results.select(&:failed?).map(&:error_message).join(", "))
        end

        { result: result, refund_amount: adjustment_amount }
      end

      # Internal: raise an exception if any of the invoices failed to zero out
      #
      # results_from_zuora: an array of results of the zero out operation
      #
      # Raises ::Billing::Zuora::ZeroOutError if at least one invoice does not zero out
      sig  do
        params(
          results_from_zuora: T::Array[GitHub::Billing::Result]
        ).returns(GitHub::Billing::Result)
      end
      def process_results(results_from_zuora)
        result = T.must(results_from_zuora.detect(&:failed?) || results_from_zuora.first)
        raise ::Billing::Zuora::ZeroOutError.new(result.error_message) if result.failed?
        result
      end

      sig do
        params(adjustment_amount: Billing::Money)
          .returns({ result: GitHub::Billing::Result, refund_amount: Billing::Money })
      end
      def default_response(adjustment_amount:)
        { result: GitHub::Billing::Result.success, refund_amount: adjustment_amount }
      end
    end
  end
end
