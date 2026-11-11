# typed: strict
# frozen_string_literal: true

module Sponsors
  class StripeInvoicesLoader
    class InvoiceStatus < T::Enum
      enums do
        Open = new("open")
        Paid = new("paid")
      end
    end

    sig { params(customer_id: String, status: InvoiceStatus, limit: Integer).void }
    def initialize(customer_id:, status:, limit:)
      @customer_id = customer_id
      @status      = status
      @limit       = limit
    end

    sig { returns(FetchResult) }
    def fetch
      stripe_response = begin
        fetch_invoices!
      rescue Stripe::InvalidRequestError => err
        return FetchResult.failure(error: err.message.to_s, status_filter: status)
      end

      FetchResult.success(response: stripe_response, status_filter: status)
    end

    private

    sig { returns(String) }
    attr_reader :customer_id

    sig { returns(Integer) }
    attr_reader :limit

    sig { returns(InvoiceStatus) }
    attr_reader :status

    sig { returns(Stripe::ListObject) }
    def fetch_invoices!
      params = {
        customer: customer_id,
        status: status.serialize,
        limit: limit,
      }

      Stripe::Invoice.list(params)
    end

    class FetchResult
      sig do
        params(
          invoices: T::Array[Stripe::Invoice],
          status_filter: InvoiceStatus,
          error: T.nilable(String)
        ).void
      end
      def initialize(invoices:, status_filter:, error:)
        @invoices      = invoices
        @status_filter = status_filter
        @error         = error
      end

      sig { returns(T::Array[Stripe::Invoice]) }
      attr_reader :invoices

      sig { returns(InvoiceStatus) }
      attr_reader :status_filter

      sig { returns(T.nilable(String)) }
      attr_reader :error

      sig { params(response: Stripe::ListObject, status_filter: InvoiceStatus).returns(FetchResult) }
      def self.success(response:, status_filter:)
        new(invoices: response["data"], status_filter: status_filter, error: nil)
      end

      sig { params(error: String, status_filter: InvoiceStatus).returns(FetchResult) }
      def self.failure(error:, status_filter:)
        new(invoices: [], status_filter: status_filter, error: error)
      end

      sig { returns(T::Boolean) }
      def success?
        error.blank?
      end
    end
  end
end
