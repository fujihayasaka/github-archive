# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # KeywordRangeFilter builds lexicographic range queries for keyword-like fields
    # (including flattened fields). Elasticsearch requires both lower and upper bounds
    # for range queries on flattened fields. This filter ensures both bounds are present
    # by supplying sentinel values when only one side is provided, and compares values
    # lexicographically (no numeric coercion).
    class KeywordRangeFilter < RangeFilter
      include FlattenedKeywordRangeBounds
      require "elastomer/adapters/number_field_encoding"
      WIDTH = Elastomer::Adapters::NumberFieldEncoding::WIDTH
      MIN_SENTINEL = "0" * WIDTH
      MAX_SENTINEL = "9" * WIDTH

      # Encode numeric-looking strings into the monotonic, order-preserving
      # fixed-width format. Leave non-numeric values (including "*") as-is.
      def encode_if_numeric(str)
        return str if str.nil? || str == "*"
        Elastomer::Adapters::NumberFieldEncoding.encode(str) || str
      end

      # Internal: Generate a range or term filter by first normalizing numeric
      # tokens to monotonic encodings so lexicographic order matches numeric order.
      # Also handles :exists/:missing symbols for existence queries.
      def range_filter_for(value)
        # Handle existence symbols - preserve them as they are
        return value if value == :exists || value == :missing

        value = value.to_s.strip
        match = RANGE_EXPRESSION.match(value)

        if match
          comparator, single_value, from, to = match.captures
          if comparator
            encoded = encode_if_numeric(single_value)
            range_filter_hash(comparator, encoded, nil, nil)
          else
            left  = encode_if_numeric(from)
            right = encode_if_numeric(to)
            range_filter_hash(nil, nil, left, right)
          end
        else
          range_filter_value(encode_if_numeric(value))
        end
      end

      # Internal: Given the arguments parsed out of a range expression, build a
      # range filter document the way ElasticSearch wants it. If comparator is
      # nil, then value is ignored and the range filter is constructed using
      # from and to.
      #
      # For flattened keyword fields Elasticsearch requires both a lower and an
      # upper bound. If only one is provided, we complete the missing bound with
      # a sentinel value that spans the full lexicographic space for typical
      # keyword data.
      def range_filter_hash(comparator, value, from, to)
        bounds = build_flattened_range_bounds(
          comparator,
          value,
          from,
          to,
          min_sentinel: MIN_SENTINEL,
          max_sentinel: MAX_SENTINEL,
        )
        validate_range_hash(bounds)
        { range: { field => bounds } } if bounds.present?
      end

      # Override: treat values as plain strings; do not enforce numeric-only values.
      def validate_value(_value)
        # No-op: any string is acceptable for keyword range comparisons.
      end

      # Override: prevent numeric coercion; comparison is lexicographic for strings.
      def try_numeric(str)
        str
      end

      # Override: Handle special :exists and :missing symbols like TermFilter
      def build(values)
        return if values.blank?

        if values.include?(:missing)
          { bool: { must_not: { exists: { field: field } } } }
        elsif values.include?(:exists)
          { exists: { field: field } }
        else
          super
        end
      end

    end
  end
end
