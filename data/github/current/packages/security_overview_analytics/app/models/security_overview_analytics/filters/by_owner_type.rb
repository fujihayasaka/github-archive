# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    class ByOwnerType
      extend T::Sig
      include Filter

      sig do
        params(
          incl_filters: T.nilable(T::Array[String]),
          excl_filters: T.nilable(T::Array[String]),
          business: Business,
          authorized_owners: T::Array[T.any(Organization, User)],
        )
        .void
      end
      def initialize(incl_filters, excl_filters, business, authorized_owners)
        @incl_filters = incl_filters
        @excl_filters = excl_filters
        @business = business
        @authorized_owners = authorized_owners
      end

      sig { override.params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def apply(rel)
        if @incl_filters.present?
          rel = where(rel, @incl_filters)
        end

        if @excl_filters.present?
          rel = where(rel, @excl_filters, neg: true)
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
          rel.and(Repository.where.not(owner_type: filters))
        else
          rel.and(Repository.where(owner_type: filters))
        end
      end

      sig { params(filters: T::Array[String]).returns(T::Array[String]) }
      def get_owner_types(filters)
        filters.filter_map do |filter|
          if filter.downcase == "organization"
            "ORGANIZATION"
          elsif filter.downcase == "user"
            feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
            feature.feature_available_for_user_repositories? ? "USER" : nil
          end
        end
      end
    end
  end
end
