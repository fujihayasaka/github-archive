# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    module Upgrade
      class MonthlySpendingComponent < ApplicationComponent
        BilledItemType = T.type_alias do
          {
            label: String,
            cost: T.nilable(Billing::Money),
            quantity: Integer,
            unit: String,
            allow_removal: T::Boolean,
            removal_text: T.nilable(String),
            removal_button_text: T.nilable(String),
            show_info: T.nilable(T::Boolean),
            info: T.nilable(String),
            id: String,
          }
        end

        sig { returns(Business) }
        attr_reader :business

        sig { returns(T::Array[BilledItemType]) }
        attr_reader :billed_items

        sig { params(business: Business, billed_items: T::Array[BilledItemType]).void }
        def initialize(business:, billed_items:)
          @business = T.let(business, Business)
          @billed_items = T.let(billed_items, T::Array[BilledItemType])
        end
      end
    end
  end
end
