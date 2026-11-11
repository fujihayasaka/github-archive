# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    module Customers
      class PaymentMethodCardComponent < ApplicationComponent
        sig { params(customer: Customer, payment_method: T.nilable(PaymentMethod)).void }
        def initialize(customer:, payment_method:)
          @customer = customer
          @payment_method = payment_method
        end

        private

        sig { returns(Customer) }
        attr_reader :customer

        sig { returns(T.nilable(PaymentMethod)) }
        attr_reader :payment_method

        sig { returns(T::Boolean) }
        def has_payment_method?
          payment_method.present?
        end

        sig { returns(String) }
        def processor_type
          payment_method&.payment_processor_type&.titleize || "Unknown"
        end

        sig { returns(T::Boolean) }
        def has_valid_token?
          payment_method&.valid_payment_token? || false
        end

        sig { returns(String) }
        def card_country
          payment_method&.country || "N/A"
        end

        sig { returns(T::Boolean) }
        def is_blocklisted?
          payment_method&.blocklisted? || false
        end

        sig { returns(T.nilable(String)) }
        def processor_customer_id
          payment_method&.payment_processor_customer_id
        end

        sig { returns(T.untyped) }
        def card_fingerprint
          payment_method&.card_fingerprint
        end
      end
    end
  end
end
