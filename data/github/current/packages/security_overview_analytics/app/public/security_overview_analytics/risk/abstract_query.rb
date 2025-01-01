# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Risk
    class AbstractQuery
      extend T::Helpers
      include GitHub::Memoizer
      include GitHub::SecurityCenter::TenantFilteringHelper

      abstract!

      RiskQueryParser = ::Search::Queries::SecurityCenter::RiskQueryParser

      sig do
        params(
          business: ::Business,
          organizations: T::Hash[Symbol, T::Array[::Organization]],
          user: ::User,
          parser: RiskQueryParser,
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
          parser: RiskQueryParser,
          repo_ids_by_feature: T.nilable(T::Hash[Symbol, T::Array[Integer]]),
        ).returns(T.attached_class)
      end
      def self.for_organization(organization:, user:, user_session:, parser:, repo_ids_by_feature: nil)
        query = ::Search::Queries::SecurityCenter::QueryParser.new(parser.query_string)
        new(
          scope: organization,
          user:,
          parser:,
          repos_filterer: Dashboards::OrgReposFilterer.new(
            organization:,
            allowed_repo_ids_by_feature: repo_ids_by_feature&.transform_keys(&:to_s),
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
          parser: RiskQueryParser,
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

      sig { returns(T::Boolean) }
      def include_user_repos?
        @repos_filterer.is_a?(Dashboards::EnterpriseReposFilterer) && @repos_filterer.include_user_repos?
      end

      sig { params(repo: Repository, feature: Symbol).returns(T::Boolean) }
      def can_see_alerts?(repo, feature)
        # At the organization scope, all organization members can see the page,
        # with data access granted by feature FGPs
        if @repos_filterer.is_a?(Dashboards::OrgReposFilterer)
          # Null represents a user can see _all_ alert types for all repostiories (organization owner or security manager)
          return true if @repos_filterer.allowed_repo_ids_by_feature.nil?
          # If access _is_ restricted, user must have access to see this feature type for this repository
          return T.must(@repos_filterer.allowed_repo_ids_by_feature)[feature.to_s]&.include?(repo.id) || false
        end

        # At enterprise scope, data access is granted by having an FGP on an org role.
        if @repos_filterer.is_a?(Dashboards::EnterpriseReposFilterer)
          if repo.owner_type.downcase == "organization"
            authorized_orgs =
              case feature
              when :code_scanning
                T.must(@repos_filterer.authorized_orgs_by_action[:read_code_scanning])
              when :dependabot_alerts
                T.must(@repos_filterer.authorized_orgs_by_action[:view_dependabot_alerts])
              when :secret_scanning
                T.must(@repos_filterer.authorized_orgs_by_action[:view_secret_scanning_alerts])
              else
                []
              end

            return authorized_orgs.map(&:id).include?(repo.owner_id)
          end

          return @repos_filterer.include_user_repos?
        end

        false
      end

      sig { params(repo: Repository, feature: Symbol).returns(T::Boolean) }
      def eligible_for_alerts?(repo, feature)
        # For organization-owned repositories, all feature types are eligible
        return true if repo.repository&.owner&.organization?
        # Foruser/emu-owned repositories, only secret scanning alerts are shown
        feature == :secret_scanning
      end

      sig { params(rel: T.any(WillPaginate::Collection, ActiveRecord::Relation)).returns(T::Array[Repository]) }
      def apply_tenant_filter(rel)
        request_scope = @scope.is_a?(::Business) ? :business : :organization
        filter_tenant_rows(
          RequestScope.new(request_scope, @scope, "risk"),
          rel,
          -> (r) { r.repository_id }
        ).first
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
