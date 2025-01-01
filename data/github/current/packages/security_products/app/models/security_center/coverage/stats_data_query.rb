# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    class StatsDataQuery
      include GitHub::Memoizer

      CoverageQueryParser = ::Search::Queries::SecurityCenter::CoverageQueryParser

      sig { returns(User) }; attr_reader :user
      sig { returns(UserSession) }; attr_reader :user_session
      sig { returns(T.any(Organization, Business)) }; attr_reader :scope
      sig { returns(CoverageQueryParser) }; attr_reader :parser
      sig { returns(T::Array[Organization]) }; attr_reader :organizations
      sig { returns(T.nilable(T::Array[Integer])) }; attr_reader :repo_ids

      class Stat < T::Struct

        const :disabled_count, Integer
        const :enabled_count, Integer
        const :feature_type, Symbol
        const :subfeature_stats, T::Array[Stat], default: []
        const :total_count, Integer

        sig { params(other: Stat).returns(T::Boolean) }
        def ==(other)
          self.disabled_count == other.disabled_count &&
            self.enabled_count == other.enabled_count &&
            self.feature_type == other.feature_type &&
            self.total_count == other.total_count &&
            self.subfeature_stats == other.subfeature_stats
        end
      end

      sig do
        params(
          business: Business,
          organizations: T::Array[Organization],
          user: User,
          user_session: UserSession,
          parser: CoverageQueryParser
        ).returns(T.attached_class)
      end
      def self.for_organizations(business:, organizations:, user:, user_session:, parser:)
        new(user: user, user_session: user_session, scope: business, organizations: organizations, parser: parser, repo_ids: nil)
      end

      sig do
        params(
          organization: Organization,
          user: User,
          user_session: UserSession,
          parser: CoverageQueryParser,
          repo_ids: T.nilable(T::Array[Integer])
        ).returns(T.attached_class)
      end
      def self.for_organization(organization:, user:, user_session:, parser:, repo_ids: nil)
        new(user: user, user_session: user_session, scope: organization, organizations: ([organization]), parser: parser, repo_ids: repo_ids)
      end

      private_class_method :new

      sig do
        params(
          user: User,
          user_session: UserSession,
          scope: T.any(Organization, Business),
          parser: CoverageQueryParser,
          organizations: T::Array[Organization],
          repo_ids: T.nilable(T::Array[Integer])
        ).void
      end
      def initialize(user:, user_session:, scope:, parser:, organizations:, repo_ids: nil)
        @user = user
        @user_session = user_session
        @scope = scope
        @parser = parser
        @organizations = organizations
        @repo_ids = repo_ids
      end

      sig { returns(T::Array[Stat]) }
      def run
        return [] if visible_features.empty?

        GitHub.dogstats.distribution_time("security_center.coverage_stats_data_query.run.dist", tags: datadog_tags) do
          query_stats
        end
      end

      private

      sig { returns(T::Array[Stat]) }
      def query_stats
        include_emus = ::SecurityCenter::FeatureFlagHelper.allows_emu_owned_repositories?(scope) &&
          scope.is_a?(Business) &&
          SecurityProduct::Permissions::BusinessAuthz.new(T.cast(scope, Business), actor: user).can_view_user_owned_repository_alerts?

        org_query = stats_query_segment_by_owner_type(owner_type: "ORGANIZATION", owners: organizations)
        results = if include_emus
          user_query = stats_query_segment_by_owner_type(owner_type: "USER", owners: [])
          query_with_union = Arel.sql("#{org_query.to_sql} UNION ALL #{user_query.to_sql}")
          RepositorySecurityCenterConfig.connection.select_rows(query_with_union)
        else
          # This ensures the end result is still an unstructured set of data
          RepositorySecurityCenterConfig.connection.select_rows(org_query)
        end
        results_by_feature_type = results.group_by { |row| row[0] }

        # Here we may to have results for both orgs and users
        # If so, we have to sum the org + user results by each feature_type
        counts = {}
        results_by_feature_type.map do |feature_type, results|
          # Ignore the feature_type (arr[0]) and owner_type (arr[3])
          # Sum up elements at the same position
          enrolled_count, not_enrolled_count = *results
            .map { |arr| [arr[1], arr[2]] }
            .transpose
            .map(&:sum)

          counts[feature_type.to_sym] = {
            enrolled_count:,
            not_enrolled_count:,
          }
        end

        visible_features.map do |feature|
          subfeature_stats = RepositorySecurityCenterStatus
            .subfeatures_for(feature)
            .reject { |subfeature| subfeature == :dependabot_version_updates } # hide subfeature from user (github/security-center#1547)
            .map do |subfeature|
              enabled_count = counts.dig(subfeature, :enrolled_count)&.to_i || 0
              disabled_count = counts.dig(subfeature, :not_enrolled_count)&.to_i || 0
              Stat.new(
                disabled_count:,
                enabled_count:,
                feature_type: subfeature,
                total_count: (enabled_count + disabled_count)
              )
            end

          enabled_count = counts.dig(feature, :enrolled_count)&.to_i || 0
          disabled_count = counts.dig(feature, :not_enrolled_count)&.to_i || 0
          Stat.new(
            disabled_count:,
            enabled_count:,
            feature_type: feature,
            subfeature_stats: subfeature_stats,
            total_count: (enabled_count + disabled_count)
          )
        end
      end

      sig { returns(T::Array[Symbol]) }
      memoize def visible_features
        SecurityFeatures.visible_features(scope).map(&:to_sym)
      end

      sig { returns(T::Array[T.untyped]) }
      def filters
        filters_list = T.let([
          ::SecurityCenter::Filters::ByRepository.new(*@parser.values_without_qualifiers, substring_match: true, scope: scope),
          ::SecurityCenter::Filters::ByArchived.new(*@parser.values_for_qualifier(CoverageQueryParser::ARCHIVED)),
          ::SecurityCenter::Filters::ByFeature.new(*@parser.values_for_qualifier(CoverageQueryParser::CODE_SCANNING), feature: :code_scanning, scope: scope),
          ::SecurityCenter::Filters::ByFeature.new(*@parser.values_for_qualifier(CoverageQueryParser::CODE_SCANNING_DEFAULT_SETUP), feature: :code_scanning_auto_codeql, scope: scope),
          ::SecurityCenter::Filters::ByFeature.new(*@parser.values_for_qualifier(CoverageQueryParser::CODE_SCANNING_PR_ALERTS), feature: :code_scanning_pr_reviews, scope: scope),
          ::SecurityCenter::Filters::ByFeature.new(*@parser.values_for_qualifier(CoverageQueryParser::DEPENDABOT_ALERTS), feature: :dependabot_alerts, scope: scope),
          ::SecurityCenter::Filters::ByFeature.new(*@parser.values_for_qualifier(CoverageQueryParser::DEPENDABOT_SECURITY_UPDATES), feature: :dependabot_security_updates, scope: scope),
          ::SecurityCenter::Filters::ByVisibility.new(*@parser.values_for_qualifier(CoverageQueryParser::VISIBILITY)),
          ::SecurityCenter::Filters::ByRepository.new(*@parser.values_for_qualifier(CoverageQueryParser::REPOSITORY), scope: scope),
          ::SecurityCenter::Filters::ByFeature.new(*@parser.values_for_qualifier(CoverageQueryParser::SECRET_SCANNING), feature: :secret_scanning, scope: scope),
          ::SecurityCenter::Filters::ByFeature.new(*@parser.values_for_qualifier(CoverageQueryParser::SECRET_SCANNING_PUSH_PROTECTION), feature: :secret_scanning_push_protection, scope: scope),
          ::SecurityCenter::Filters::ByTeam.new(*@parser.values_for_qualifier(CoverageQueryParser::TEAM), organizations: organizations, user: user),
          ::SecurityCenter::Filters::ByTopic.new(*@parser.values_for_qualifier(CoverageQueryParser::TOPIC), organizations: organizations),
          ::SecurityCenter::Filters::ByGhas.new(*@parser.values_for_qualifier(CoverageQueryParser::ADVANCED_SECURITY)),
        ], T::Array[T.untyped])

        addition_filters_list =
          if @scope.is_a?(Business)
            [
              ::SecurityCenter::Filters::ByOwner.new(*@parser.values_for_qualifier(CoverageQueryParser::OWNER), @scope),
              ::SecurityCenter::Filters::ByOwnerType.new(*@parser.values_for_qualifier(CoverageQueryParser::OWNER_TYPE), @scope)
            ]
          else
            [::SecurityCenter::Filters::ByCustomProperty.new(
              allowed_repo_ids: repo_ids,
              org: @scope,
              query: parser.custom_properties_query_string,
              user: user,
              user_session: user_session
            )]
          end
        filters_list.concat(addition_filters_list)

        filters_list.compact
      end

      sig { returns(T::Array[String]) }
      def datadog_tags
        tags = []
        tags << "scope:#{scope.class.name&.demodulize.underscore}"
        tags << "data_query_ver:2"

        filters.each do |filter|
          next unless filter.respond_to?(:is_empty?)
          next if filter.is_empty?
          tags << "has_filter:#{filter.class.name.demodulize.underscore}"
        end

        tags
      end

      sig { params(owner_type: String, owners: T::Array[::Organization]).returns(ActiveRecord::Relation) }
      def stats_query_segment_by_owner_type(owner_type:, owners:)
        base_query = RepositorySecurityCenterConfig.none
        if owner_type == "ORGANIZATION"
          biz = @scope.is_a?(Business) ? @scope : @scope.business
          base_query = RepositorySecurityCenterConfig
            .with_owners_under_business(biz, owners, include_emus: false)
        elsif owner_type == "USER"
          base_query = RepositorySecurityCenterConfig.where(business: @scope, owner_type: "USER")
        else
          return RepositorySecurityCenterConfig.none
        end

        base_query
          .joins(%{
            INNER JOIN #{RepositorySecurityCenterStatus.table_name}
              ON #{RepositorySecurityCenterStatus.table_name}.owner_id = #{RepositorySecurityCenterConfig.table_name}.owner_id
              AND #{RepositorySecurityCenterStatus.table_name}.repository_id = #{RepositorySecurityCenterConfig.table_name}.repository_id
          })
          .then do |rel|
            next rel if repo_ids.nil?
            rel.where(repository_id: repo_ids)
          end
          .then { |rel| filters.reduce(rel) { |r, filter| filter.apply(r) } }
          .group(:feature_type)
          .select(
            "#{RepositorySecurityCenterStatus.table_name}.feature_type",
            Arel.sql("sum(if(#{RepositorySecurityCenterStatus.table_name}.scanning_status = 'enrolled', 1, 0)) as enrolled_count"),
            Arel.sql("sum(if(#{RepositorySecurityCenterStatus.table_name}.scanning_status != 'enrolled', 1, 0)) as not_enrolled_count"),
            Arel.sql("? AS owner_type", owner_type),
          )
      end
    end
  end
end
