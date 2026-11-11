# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    class ByOrganization
      include Filter

      sig do
        params(
          incl_filters: T::Array[String],
          excl_filters: T::Array[String],
          authorized_orgs: T::Array[Organization],
        )
        .void
      end
      def initialize(incl_filters, excl_filters, authorized_orgs:)
        @incl_filters = T.let(incl_filters.map(&:downcase), T::Array[String])
        @excl_filters = T.let(excl_filters.map(&:downcase), T::Array[String])
        @authorized_orgs = authorized_orgs
      end

      sig { override.params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def apply(rel)
        # NOTE: authorized orgs are filtered in the base query

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
        org_ids = @authorized_orgs.filter_map { |org| org.id if filters.include? org.display_login.downcase }

        if neg
          rel.where.not(organization_id: org_ids)
        else
          rel.where(organization_id: org_ids)
        end
      end
    end
  end
end
