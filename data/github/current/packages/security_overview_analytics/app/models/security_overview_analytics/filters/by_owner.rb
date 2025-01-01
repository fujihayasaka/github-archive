# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    class ByOwner
      extend T::Sig
      include Filter

      sig do
        params(
          incl_filters: T::Array[String],
          excl_filters: T::Array[String],
          business: Business,
          authorized_owners: T::Array[T.any(Organization, User)],
        )
        .void
      end
      def initialize(incl_filters, excl_filters, business, authorized_owners)
        @incl_filters = T.let(incl_filters.map(&:downcase), T::Array[String])
        @excl_filters = T.let(excl_filters.map(&:downcase), T::Array[String])
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
        org_ids = @authorized_owners.filter_map { |owner| owner.id if owner.is_a?(Organization) && filters.include?(owner.display_login.downcase) }

        user_ids = ::SecurityCenter::Helpers::EnterpriseManagedUsers.new(business: @business).find_ids(logins: filters)
        where_clause = { owner_id: org_ids + user_ids }

        if neg
          rel.and(Repository.where.not(where_clause))
        else
          rel.and(Repository.where(where_clause))
        end
      end
    end
  end
end
