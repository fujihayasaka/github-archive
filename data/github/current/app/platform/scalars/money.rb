# typed: true
# frozen_string_literal: true

module Platform
  module Scalars
    class Money < Platform::Scalars::Base
      description "A monetary amount represented in the ISO 4217 currency code."
      visibility :internal

      def self.coerce_input(value, context)
        fractional, currency = value
        if fractional.is_a?(Integer) && currency.is_a?(String)
          Billing::Money.new(fractional, currency)
        end
      end

      def self.coerce_result(money, context)
        [money.fractional, money.currency.to_s]
      end
    end
  end
end
