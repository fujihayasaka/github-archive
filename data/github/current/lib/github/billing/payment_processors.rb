# typed: strict
# frozen_string_literal: true

module GitHub::Billing
  module PaymentProcessors
    extend T::Sig

    autoload :BraintreeProcessor, "github/billing/payment_processors/braintree_processor"
    autoload :PaymentProcessor, "github/billing/payment_processors/payment_processor"
    autoload :ZuoraProcessor, "github/billing/payment_processors/zuora_processor"

    # Public: Factory to create a specific PaymentProcessor based on known
    # types.
    #
    # type        - String type to create. Registered types are:
    #               - "braintree"
    #               - "zuora"
    # customer_id - String customer id that maps to the external payment
    #               processors system.
    #
    # gateway - Billing::Zuora::PaymentGateway only required when type is "zuora".
    #           Used to determine which gateway to assign when updating payment details to Zuora
    #
    sig { params(type: String, customer_id: String, gateway: T.nilable(Billing::Zuora::PaymentGateway)).returns(PaymentProcessor) }
    def self.create(type, customer_id, gateway: nil)
      case type
      when "braintree"
        BraintreeProcessor.new(customer_id)
      when "zuora"
        ZuoraProcessor.new(customer_id, gateway: T.must(gateway))
      else
        raise ArgumentError, "Unknown payment processor type: #{type}"
      end
    end
  end
end
