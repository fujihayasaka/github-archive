# typed: true
# frozen_string_literal: true

# GitHub subclass of Money that always uses the default bank for currency
# conversions.
#
# See for more details:
#   https://github.com/github/github/issues/57188
#   https://github.com/github/github/pull/57608
module Billing
  class Money < ::Money
    require "monetize"

    # Set default rounding mode and currency to prevent warning from default deprecation
    # Inheriting from Money sets defaults as seen here https://github.com/RubyMoney/money/blob/265de50b987b8c69261dde013c8dd18a567279df/lib/money/money.rb#L208-L210
    # That setup overrides setting in config/initializers/money.rb
    # Setting the rounding mode and default currency here ensures we don't trigger the warning
    ::Money.rounding_mode = BigDecimal::ROUND_HALF_EVEN
    ::Money.default_currency = "USD"
    self.rounding_mode = BigDecimal::ROUND_HALF_EVEN
    self.default_currency = "USD"

    def self.parse(input)
      parsed = ::Monetize.parse(input, ::Money.default_currency, { bank: ::GitHub::Billing::Currency.default_bank })
      new(parsed.fractional)
    end

    def initialize(obj, currency = default_currency, bank = self.bank)
      super(obj, currency, bank)
    end

    def bank
      default_bank
    end

    def ==(other)
      # N.B: the superclass implementation of equality returns true when
      #      comparing zero money with a numeric zero. This is generally
      #      unexpected and has caused us to let type errors slip through
      #      our unit tests
      return false unless other.is_a?(Money)
      super
    end

    private

    def default_currency
      ::Money.default_currency
    end

    def default_bank
      GitHub::Billing::Currency.default_bank
    end
  end
end
