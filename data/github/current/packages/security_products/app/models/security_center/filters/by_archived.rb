# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Filters
    class ByArchived

      sig { params(incl_filters: T::Array[String], excl_filters: T::Array[String]).void }
      def initialize(incl_filters, excl_filters)
        @incl_filters = T.let(incl_filters.uniq.map(&:to_sym), T::Array[Symbol])
        @excl_filters = T.let(excl_filters.uniq.map(&:to_sym), T::Array[Symbol])
      end

      sig { params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def apply(rel)
        if @incl_filters.present?
          valid_filters = select_valid_filters(@incl_filters)
          return rel.none if valid_filters.empty?
          rel = rel.where(archived: valid_filters)
        end

        if @excl_filters.present?
          valid_filters = select_valid_filters(@excl_filters)
          return rel if valid_filters.size < @excl_filters.size
          rel = rel.where.not(archived: valid_filters)
        end

        rel
      end

      sig { returns(T::Boolean) }
      def is_empty?
        @incl_filters.blank? && @excl_filters.blank?
      end

      private

      sig { params(filters: T::Array[Symbol]).returns(T::Array[Symbol]) }
      def select_valid_filters(filters)
        filters.select { |f| [:true, :false].include?(f) }
      end

      sig { returns(T.nilable(Integer)) }
      def get_maintained_value
        if @incl_filters.present?
          maintained = @incl_filters.include?(:false) ? 1 : 0
        end

        if @excl_filters.present?
          maintained = @excl_filters.include?(:false) ? 0 : 1
        end

        # If both positive filters are provided without any negations present, no need to filter
        # because we're selecting all repos
        return if @incl_filters.sort == [:true, :false].sort
        maintained
      end
    end
  end
end
