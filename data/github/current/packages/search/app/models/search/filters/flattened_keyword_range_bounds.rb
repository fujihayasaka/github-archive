# typed: true
# frozen_string_literal: true

module Search
  module Filters
    # Mixin providing a helper to build range bound hashes for keyword-like
    # fields (including flattened) where Elasticsearch requires both bounds.
    # It fills the missing side with caller-provided sentinel values.
    #
    # Note: This helper returns only the bounds hash (e.g., { gte: ..., lte: ... })
    # and does not call `validate_range_hash` or wrap with `{ range: { field => ... } }`.
    # Callers should perform validation and wrapping.
    module FlattenedKeywordRangeBounds
      # Build the bounds hash with sentinels for missing sides; returns a Hash,
      # or an empty Hash if unconstrained (e.g., *..*).
      def build_flattened_range_bounds(comparator, value, from, to, min_sentinel:, max_sentinel:)
        hash = {}

        value = value.dup unless value.nil?
        from  = from.dup  unless from.nil?
        to    = to.dup    unless to.nil?

        case comparator
        when ">";  hash[:gt]  = value
        when ">="; hash[:gte] = value
        when "<";  hash[:lt]  = value
        when "<="; hash[:lte] = value
        else
          hash[:gte] = from if from != "*"
          hash[:lte] = to   if to != "*"
        end

        # Ensure both bounds for flattened keyword behavior without over-constraining.
        case comparator
        when ">", ">="
          hash[:lte] ||= max_sentinel
        when "<", "<="
          hash[:gte] ||= min_sentinel
        else
          if hash.key?(:gte) && !hash.key?(:lte)
            hash[:lte] = max_sentinel
          elsif hash.key?(:lte) && !hash.key?(:gte)
            hash[:gte] = min_sentinel
          end
        end

        hash
      end
    end
  end
end
