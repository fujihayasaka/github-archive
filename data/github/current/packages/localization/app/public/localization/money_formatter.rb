# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Localization
  class MoneyFormatter
    CurrencyFormatter = Class.new { include ActionView::Helpers::NumberHelper }

    def initialize(config: self.class.default_configuration, rounder: NearestTenRoundingStrategy.new)
      @config = config
      @formatter = CurrencyFormatter.new
      @rounder = rounder
    end

    # :precision - Sets the level of precision (defaults to 2).
    # :unit - Sets the denomination of the currency (defaults to “$”).
    # :separator - Sets the separator between the units (defaults to “.”).
    # :delimiter - Sets the thousands delimiter (defaults to “,”).
    # :format - Sets the format for non-negative numbers (defaults to “%u%n”). Fields are %u for the currency, and %n for the number.
    # :negative_format - Sets the format for negative numbers (defaults to prepending a hyphen to the formatted number given by :format). Accepts the same fields than :format, except %n is here the absolute value of the number.
    # :raise - If true, raises InvalidNumberError when the argument is invalid.
    # :integer_precision - Sets the level of precision for integer values, or equivalent to integers I.E. 1.0
    def format(money, options = {})
      options = options_for(money, options)

      amount = @rounder.round(money.to_f)

      if (amount % 1).zero?
        options[:precision] = options[:integer_precision] || options[:precision]
      end

      if options[:unit] == false
        options.delete(:unit)
        return @formatter.number_with_precision(amount, options)
      end

      @formatter.number_to_currency(amount, options)
    end

    # @param money [Money]
    # @return [Boolean]
    def symbol_first?(money)
      options = @config.lookup(money)
      options[:format].to_s[1] == "u"
    end

    def self.default_configuration
      @default_configuration ||= Localization::CurrencyConfiguration::YamlConfig.new
    end

    private

    def options_for(money, overrides = {})
      @config.lookup(money).merge(overrides)
    end
  end
end
