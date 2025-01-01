# typed: true
# frozen_string_literal: true

module Localization
  class MoneyFormatter
    class NearestTenRoundingStrategy
      def initialize(min_for_nearest_ten: 100, min_for_integer: 10)
        @min_for_nearest_ten = min_for_nearest_ten.to_i
        @min_for_integer = min_for_integer.to_i
      end

      def round(value)
        if to_nearest_ten?(value)
          return to_nearest_ten(value)
        end

        if to_int?(value)
          return to_int(value)
        end

        value
      end

      private

      def to_nearest_ten(value)
        remainder = value.to_i % 10

        if remainder.zero?
          return value.to_i
        end

        if remainder >= 5
          return value.to_i + (10 - remainder)
        end

        value.to_i - remainder
      end

      def to_nearest_ten?(value)
        value >= @min_for_nearest_ten
      end

      def to_int?(value)
        value > @min_for_integer
      end

      def to_int(value)
        remainder = value % 1

        if remainder >= 0.5
          return value.to_i + 1
        end

        value.to_i
      end
    end
  end
end
