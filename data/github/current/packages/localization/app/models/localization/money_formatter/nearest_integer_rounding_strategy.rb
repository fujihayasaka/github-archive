# typed: true
# frozen_string_literal: true

module Localization
  class MoneyFormatter
    class NearestIntegerRoundingStrategy < NearestTenRoundingStrategy

      def round(value)
        if to_int?(value)
          return to_int(value)
        end

        value
      end
    end
  end
end
