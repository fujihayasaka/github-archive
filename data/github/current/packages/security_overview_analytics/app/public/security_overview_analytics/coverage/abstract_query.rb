# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Coverage
    class AbstractQuery
      extend T::Helpers
      include GitHub::Memoizer

      abstract!

      CoverageQueryParser = ::Search::Queries::SecurityCenter::CoverageQueryParser

      sig do
        params(
          business: ::Business,
          organizations: T::Array[Organization],
          user: ::User,
          parser: CoverageQueryParser,
        ).returns(T.attached_class)
      end
      def self.for_business(business:, organizations:, user:, parser:)
        query = ::Search::Queries::SecurityCenter::QueryParser.new(parser.query_string)
        new(
          scope: business,
          user:,
          parser:,
          repos_filterer: Dashboards::EnterpriseReposFilterer.new(
            business:,
            organizations:,
            user:,
            query:,
          ),
          features_filterer: Filters::FeatureStatusSummary::Filterer.new(query),
        )
      end

      sig do
        params(
          organization: ::Organization,
          user: ::User,
          user_session: ::UserSession,
          parser: CoverageQueryParser,
          repo_ids: T.nilable(T::Array[Integer]),
        ).returns(T.attached_class)
      end
      def self.for_organization(organization:, user:, user_session:, parser:, repo_ids: nil)
        query = ::Search::Queries::SecurityCenter::QueryParser.new(parser.query_string)
        new(
          scope: organization,
          user:,
          parser:,
          repos_filterer: Dashboards::OrgReposFilterer.new(
            organization:,
            allowed_repo_ids_by_feature: \
              unless repo_ids.nil?
                {
                  ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS => repo_ids,
                  ::SecurityCenter::SecurityFeatures::CODE_SCANNING => repo_ids,
                  ::SecurityCenter::SecurityFeatures::SECRET_SCANNING => repo_ids,
                }
              end,
            user:,
            user_session:,
            query:,
          ),
          features_filterer: Filters::FeatureStatusSummary::Filterer.new(query),
        )
      end

      # Require callers to use scoped factory methods above
      private_class_method :new

      sig do
        params(
          scope: T.any(::Business, ::Organization),
          user: ::User,
          parser: CoverageQueryParser,
          repos_filterer: Dashboards::ReposFilterer,
          features_filterer: Filters::FeatureStatusSummary::Filterer,
        ).void
      end
      def initialize(scope:, user:, parser:, repos_filterer:, features_filterer:)
        @scope = scope
        @user = user
        @parser = parser
        @repos_filterer = repos_filterer
        @features_filterer = features_filterer
      end

      protected

      sig { returns(T::Array[Symbol]) }
      memoize def visible_features
        ::SecurityCenter::SecurityFeatures.visible_features(@scope).map(&:to_sym)
      end

      sig { params(feature: Symbol).returns(String) }
      def feature_display_name_for(feature)
        RepositorySecurityCenterStatus.feature_display_name_for(feature)
      end

      sig { params(feature: Symbol).returns(String) }
      def coverage_display_name_for(feature)
        RepositorySecurityCenterStatus.coverage_display_name_for(feature)
      end

      sig { overridable.returns(T::Array[String]) }
      memoize def datadog_tags
        tags = []
        tags << "scope:#{@scope.class.name&.demodulize.underscore}"
        tags << "data_query_ver:3"

        applied_feature_filters =
          @features_filterer.filters.select { |f| !f.is_empty? }.map { |f| f.class.name.demodulize.underscore }

        applied_filters = @repos_filterer.applied_filters + applied_feature_filters

        applied_filters.each do |filter|
          tags << "has_filter:#{filter}"
        end

        tags
      end
    end
  end
end
