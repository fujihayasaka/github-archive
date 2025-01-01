# typed: strict
# frozen_string_literal: true

module GitHub::Billing
  class PaymentProcessors::PaymentProcessor
    extend T::Helpers

    abstract!

    # Public: String customer_id in the payment processor's system.
    sig { returns(T.nilable(String)) }
    attr_reader :customer_id

    # Public: Initialize a new payment processor.
    #
    # customer_id - A external id in the payment processor's system (usually
    # representing a customer).
    sig { params(customer_id: T.nilable(String), gateway: T.nilable(Billing::Zuora::PaymentGateway)).void }
    def initialize(customer_id, gateway: nil)
      @customer_id = customer_id
      @gateway = gateway
    end

    # Public: String type of this processor
    sig { returns(String) }
    def type
      self.class.name.to_s.split("::").last.to_s.downcase
    end

    sig do
      abstract
        .params(
          payment_details: GitHub::Billing::PaymentProcessorPaymentDetails,
          blk: T.nilable(T.proc.params(arg0: PaymentProcessorRecord).void)
        ).returns(GitHub::Billing::Result)
    end
    def update_payment_details(payment_details, &blk); end

    sig { abstract.returns(T::Boolean) }
    def clear_payment_details; end

    sig { abstract.params(payment_details: PaymentProcessorPaymentDetails).returns(T::Hash[Symbol, T.untyped]) }
    def update_customer_contact(payment_details:); end

    private

    sig { returns(T.nilable(Billing::Zuora::PaymentGateway)) }
    attr_reader :gateway
  end
end
