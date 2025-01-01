# typed: strict
# frozen_string_literal: true

module Elastomer::Adapters
  # NumberFieldEncoding provides a monotonic, order-preserving encoding for
  # signed numeric values as fixed-width strings suitable for lexicographic
  # range queries in flattened keyword fields.
  module NumberFieldEncoding

    # Scale to fixed precision (6 decimals)
    SCALE = T.let(1_000_000, Integer)
    # Apply positive bias to make the entire domain non-negative
    BIAS  = T.let(2_147_483_648 * SCALE, Integer)
    # Left pad with zeros to fixed width so lexicographic order == numeric order
    WIDTH = T.let(16, Integer)

    sig { params(value: T.untyped).returns(T.nilable(String)) }
    def self.encode(value)
      return nil if value.nil?

      str = value.to_s.strip
      return nil if str.empty?
      return nil unless str.match?(/\A-?\d*\.?\d+\z/)

      encode_decimal(BigDecimal(str))
    rescue ArgumentError, TypeError
      nil
    end

    sig { params(decimal: BigDecimal).returns(String) }
    def self.encode_decimal(decimal)
      scaled = (decimal * SCALE).round(0, :half_up).to_i
      (scaled + BIAS).to_s.rjust(WIDTH, "0")
    end
  end
end
