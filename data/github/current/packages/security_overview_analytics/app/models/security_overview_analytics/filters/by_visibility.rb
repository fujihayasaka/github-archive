# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    class ByVisibility
      include Filter

      sig { params(incl_filters: T.nilable(T::Array[String]), excl_filters: T.nilable(T::Array[String])).void }
      def initialize(incl_filters, excl_filters)
        @incl_filters = T.let(incl_filters&.map(&:to_s)&.map(&:downcase)&.uniq&.map(&:to_sym), T.nilable(T::Array[Symbol]))
        @excl_filters = T.let(excl_filters&.map(&:to_s)&.map(&:downcase)&.uniq&.map(&:to_sym), T.nilable(T::Array[Symbol]))
      end

      sig { override.params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
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

      sig { override.returns(T::Boolean) }
      def is_empty?
        @incl_filters.blank? && @excl_filters.blank?
      end

      sig { override.returns(T::Boolean) }
      def has_incl_filters?
        @incl_filters.present?
      end

      private

      sig { params(filters: T::Array[Symbol]).returns(T::Array[Symbol]) }
      def select_valid_filters(filters)
        valid_repo_visibilities = ::Repository::VISIBILITIES.map(&:to_sym).to_set
        filters.select { |f| valid_repo_visibilities.include?(f) }
      end
    end
  end
end
