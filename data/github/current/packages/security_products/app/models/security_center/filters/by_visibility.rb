# typed: true
# frozen_string_literal: true

module SecurityCenter
  module Filters
    class ByVisibility
      def initialize(incl_filters, excl_filters)
        @incl_filters = incl_filters&.map(&:to_s)&.map(&:downcase)&.uniq&.map(&:to_sym)
        @excl_filters = excl_filters&.map(&:to_s)&.map(&:downcase)&.uniq&.map(&:to_sym)
      end

      def apply(rel)
        if @incl_filters.present?
          valid_filters = select_valid_filters(@incl_filters)
          return rel.none if valid_filters.empty?
          rel = rel.where(visibility: valid_filters)
        end

        if @excl_filters.present?
          valid_filters = select_valid_filters(@excl_filters)
          return rel if valid_filters.size < @excl_filters.size
          rel = rel.where.not(visibility: valid_filters)
        end

        rel
      end

      def is_empty?
        @incl_filters.blank? && @excl_filters.blank?
      end

      private

      def select_valid_filters(filters)
        filters.select { |f| [:public, :internal, :private].include?(f) }
      end
    end
  end
end
