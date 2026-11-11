# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    module Customers
      class ZuoraInfoComponent < ApplicationComponent
        include GitHub::Memoizer
        include Stafftools::BillingHelper

        sig { params(customer: Customer).void }
        def initialize(customer:)
          @customer = customer
        end

        sig { returns(T::Boolean) }
        def render?
          true
        end

        private

        sig { returns(Customer) }
        attr_reader :customer

        sig { returns(T::Boolean) }
        def has_zuora_account?
          customer.zuora_account_id.present?
        end

        sig { returns(T.nilable(String)) }
        def zuora_account_number
          customer.zuora_account_number
        end

        sig { returns(T.nilable(String)) }
        def zuora_account_id
          customer.zuora_account_id
        end

        sig { returns(T::Boolean) }
        def auto_pay?
          customer.auto_pay?
        end

        sig { returns(T.untyped) }
        def bill_cycle_day
          customer.bill_cycle_day
        end

        sig { returns(String) }
        def billing_type_label
          customer.billing_type == "invoice" ? "Invoice (Sales Serve)" : "Card (Self Serve)"
        end
      end
    end
  end
end
