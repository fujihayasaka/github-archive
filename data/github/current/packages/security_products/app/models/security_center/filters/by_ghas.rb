# typed: true
# frozen_string_literal: true

module SecurityCenter
  module Filters
    class ByGhas
      VALID_STATES = %w[enabled not-enabled].freeze

      def initialize(incl_filters, excl_filters)
        @incl_filters = incl_filters&.uniq || []
        @excl_filters = excl_filters&.uniq || []
      end

      def apply(rel)
        if @incl_filters.present?
          valid_filters = select_valid_filters(@incl_filters)
          return rel.none if valid_filters.empty?
          rel = where(rel, valid_filters, negated: false)
        end

        if @excl_filters.present?
          valid_filters = select_valid_filters(@excl_filters)
          return rel if valid_filters.empty?
          rel = where(rel, valid_filters, negated: true)
        end

        rel
      end

      def is_empty?
        @incl_filters.blank? && @excl_filters.blank?
      end

      private

      def select_valid_filters(filters)
        filters.select { |f| VALID_STATES.include?(f) }
      end

      def where(rel, values, negated:)
        or_rels = []
        values.each do |value|
          filter = case value
          when "enabled"
            rel.where(ghas_enabled: !negated)
          when "not-enabled"
            rel.where(ghas_enabled: negated)
          else
            next
          end

          or_rels << filter
        end

        if negated
          rel.and(or_rels.reduce { |rel, or_rel| rel.and(or_rel) })
        else
          rel.and(or_rels.reduce { |rel, or_rel| rel.or(or_rel) })
        end
      end
    end
  end
end
