# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Filters
    class ByOwnerType

      sig do
        params(
          incl_filters: T.nilable(T::Array[String]),
          excl_filters: T.nilable(T::Array[String]),
          business: Business,
        )
        .void
      end
      def initialize(incl_filters, excl_filters, business)
        @incl_filters = incl_filters
        @excl_filters = excl_filters
        @business = business
      end

      sig { params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def apply(rel)
        if @incl_filters.present?
          rel = where(rel, @incl_filters)
        end

        if @excl_filters.present?
          rel = where(rel, @excl_filters, neg: true)
        end

        rel
      end

      private

      sig do
        params(
          rel: ActiveRecord::Relation,
          filters: T::Array[String],
          neg: T::Boolean
        ).returns(ActiveRecord::Relation)
      end
      def where(rel, filters, neg: false)
        filters = get_owner_types(filters)
        return rel.none if filters.empty? && !neg
        if neg
          rel.and(RepositorySecurityCenterConfig.where.not(owner_type: filters))
        else
          rel.and(RepositorySecurityCenterConfig.where(owner_type: filters))
        end
      end

      sig { params(filters: T::Array[String]).returns(T::Array[String]) }
      def get_owner_types(filters)
        filters.map do |filter|
          if filter == "organization"
            "ORGANIZATION"
          elsif filter == "user"
            feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
            feature.feature_available_for_user_repositories? ? "USER" : nil
          else
            nil
          end
        end.compact
      end
    end
  end
end
