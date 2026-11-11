# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    class ByState
      include Filter

      sig { params(incl_filters: T::Array[String], excl_filters: T::Array[String]).void }
      def initialize(incl_filters, excl_filters)
        @incl_filters = T.let(incl_filters.uniq.map(&:underscore).map(&:to_sym), T::Array[Symbol])
        @excl_filters = T.let(excl_filters.uniq.map(&:underscore).map(&:to_sym), T::Array[Symbol])
      end

      sig { override.params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def apply(rel)
        if @incl_filters.present?
          valid_filters = select_valid_filters(@incl_filters)
          return rel.none if valid_filters.empty?
          rel = rel.where(alert_resolved: valid_filters)
        end

        if @excl_filters.present?
          valid_filters = select_valid_filters(@excl_filters)
          return rel if valid_filters.size < @excl_filters.size
          rel = rel.where.not(alert_resolved: valid_filters)
        end

        rel
      end

      sig { override.returns(T::Boolean) }
      def is_empty?
        @incl_filters.blank? && @excl_filters.blank?
      end

      sig { override.returns(T::Boolean) }
      def has_incl_filters?
        @incl_filters.present?
      end

      private

      sig { params(filters: T::Array[Symbol]).returns(T::Array[T::Boolean]) }
      def select_valid_filters(filters)
        filters.map do |filter|
          next unless [:open, :closed].include?(filter)
          filter == :closed
        end.compact
      end
    end
  end
end
