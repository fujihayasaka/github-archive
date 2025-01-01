# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  module Filters
    class AdvancedFilters

      sig { params(user: User, org: Organization, filter_hash: T::Hash[String, T.untyped], user_session: T.nilable(UserSession)).void }
      def initialize(user, org, filter_hash, user_session = nil)
        @user = user
        @org = org
        @filter_hash = filter_hash
        @user_session = user_session
      end

      sig { returns(T::Boolean) }
      def can_apply?
        can_apply_advanced_filters?
      end

      sig { returns(T::Set[Integer]) }
      def apply
        return Set.new unless can_apply_advanced_filters?

        GitHub.dogstats.distribution_time("security_configurations.filters.advanced") do
          results = ::SecurityCenter::Coverage::ListDataQuery.for_organization(
            user: @user,
            user_session: @user_session,
            organization: @org,
            parser: advanced_filters_parser(@filter_hash["advanced_filters"]),
          ).all.pluck(:repository_id)

          Set.new(results)
        end
      end

      private

      def can_apply_advanced_filters?
        @filter_hash["advanced_filters"].present?
      end

      sig { params(advanced_query: String).returns(::Search::Queries::SecurityCenter::CoverageQueryParser) }
      def advanced_filters_parser(advanced_query)
        ::Search::Queries::SecurityCenter::CoverageQueryParser.new(advanced_query)
      end
    end
  end
end
