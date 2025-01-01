# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Filters
    class ByOwner
      extend T::Sig

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
        org_ids = @business.organizations.where(display_login: filters).pluck(:id)
        feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)

        user_ids = if feature.feature_available_for_user_repositories?
          Helpers::EnterpriseManagedUsers.new(business: @business).find_ids(logins: filters)
        else
          []
        end

        if neg
          rel.and(RepositorySecurityCenterConfig.where.not(owner_id: org_ids + user_ids))
        else
          rel.and(RepositorySecurityCenterConfig.where(owner_id: org_ids + user_ids))
        end
      end
    end
  end
end
