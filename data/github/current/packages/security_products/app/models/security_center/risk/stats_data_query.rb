# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Risk
    class StatsDataQuery
      extend T::Sig
      include GitHub::Memoizer
      include GitHub::SecurityCenter::LoggingHelper

      RiskQueryParser = ::Search::Queries::SecurityCenter::RiskQueryParser

      sig { returns(User) }; attr_reader :current_user
      sig { returns(UserSession) }; attr_reader :user_session
      sig { returns(T.any(Organization, Business)) }; attr_reader :scope
      sig { returns(RiskQueryParser) }; attr_reader :parser
      sig { returns(T::Array[Organization]) }; attr_reader :organizations
      sig { returns(T.nilable(T::Hash[Symbol, T::Array[Integer]])) }; attr_reader :repo_ids_by_feature

      class Stat < T::Struct
        extend T::Sig

        const :affected_repo_count, Integer, default: 0
        const :feature_type, Symbol
        const :open_alerts_count, Integer, default: 0
        const :open_alerts_by_severity, T::Hash[Symbol, Integer], default: {}
        const :total_repo_count, Integer, default: 0

        sig { params(other: T.untyped).returns(T::Boolean) }
        def ==(other)
          self.affected_repo_count == other.affected_repo_count &&
            self.feature_type == other.feature_type &&
            self.open_alerts_count == other.open_alerts_count &&
            self.total_repo_count == other.total_repo_count &&
            self.open_alerts_by_severity == other.open_alerts_by_severity
        end
      end

      sig do
        params(
          business: Business,
          organizations: T::Array[Organization],
          current_user: User,
          user_session: UserSession,
          parser: RiskQueryParser,
        ).returns(T.attached_class)
      end
      def self.for_organizations(business:, organizations:, current_user:, user_session:, parser:)
        new(current_user: current_user, user_session: user_session, scope: business, organizations: organizations, parser: parser, repo_ids_by_feature: nil)
      end

      sig do
        params(
          organization: Organization,
          current_user: User,
          user_session: UserSession,
          parser: RiskQueryParser,
          repo_ids_by_feature: T.nilable(T::Hash[Symbol, T::Array[Integer]])
        ).returns(T.attached_class)
      end
      def self.for_organization(organization:, current_user:, user_session:, parser:, repo_ids_by_feature: nil)
        new(current_user: current_user, user_session: user_session, scope: organization, organizations: ([organization]), parser: parser, repo_ids_by_feature: repo_ids_by_feature)
      end

      private_class_method :new

      sig do
        params(
          current_user: User,
          user_session: UserSession,
          scope: T.any(Organization, Business),
          parser: RiskQueryParser,
          organizations: T::Array[Organization],
          repo_ids_by_feature: T.nilable(T::Hash[Symbol, T::Array[Integer]])
        ).void
      end
      def initialize(current_user:, user_session:, scope:, parser:, organizations:, repo_ids_by_feature: nil)
        @current_user = current_user
        @user_session = user_session
        @scope = scope
        @parser = parser
        @organizations = organizations
        @repo_ids_by_feature = repo_ids_by_feature
      end

      sig { returns(T::Array[Stat]) }
      def run
        return [] if visible_features.empty?

        GitHub.dogstats.distribution_time("security_center.risk_stats_data_query.run.dist", tags: datadog_tags) do
          build_stats
        end
      end

      private

      sig { returns(T::Array[Stat]) }
      def build_stats
        stats =
          if repo_ids_by_feature.nil?
            # Org owners and security managers aren't subject to repo accessibility restrictions
            # Because of that, they also get a _much_ more efficient single query for these stats
            query_stats(nil, nil)
          else
            # this is the repo_ids the user can see _after_ applying any `<feature>:??` filtering
            accessible_repo_ids = ByAccessibleRepos.new(repo_ids_by_feature: repo_ids_by_feature, parser: parser).repository_ids
            accessible_repo_ids = T.must(accessible_repo_ids)

            visible_features.flat_map do |feature|
              visible_repo_ids = accessible_repo_ids & Array(T.must(repo_ids_by_feature)[feature])
              query_stats(feature, visible_repo_ids)
            end
          end

        stats_by_feature = stats.index_by(&:feature_type)
        visible_features.map { |feature| stats_by_feature[feature] || empty_stats(feature) }
      end

      sig { params(feature_type: T.nilable(Symbol), visible_repo_ids: T.nilable(T::Array[Integer])).returns(T::Array[Stat]) }
      def query_stats(feature_type, visible_repo_ids)
        include_emus = ::SecurityCenter::FeatureFlagHelper.allows_emu_owned_repositories?(scope) && emus_in_scope?

        base_query_params = if scope.is_a?(Business)
          RepositorySecurityCenterConfig
            .with_owners_under_business(scope, organizations, include_emus: include_emus)
        else
          RepositorySecurityCenterConfig.where(owner_id: organizations)
        end

        total_repo_count = log_timing(step: "query total repo count") do
          config_owner_rel = base_query_params
            .then do |rel|
              next rel if feature_type.nil? && visible_repo_ids.nil?

              statuses_rel = RepositorySecurityCenterStatus
                .where(
                  owner: organizations,
                  feature_type: feature_type,
                  repository_id: visible_repo_ids
                )
                .select(:repository_id)

              if scope.is_a?(Business)
                statuses_rel = statuses_rel.where(business_id: scope.id)
              end

              # If we're querying features separately (for non-admin users),
              # we need to filter on the provided feature and corresponding visible repos
              rel.where(repository_id: statuses_rel)
            end
            .then { |rel| filters.reduce(rel) { |r, filter| filter.apply(r) } }
            .count
        end

        stats_records = log_timing(step: "query stats") do
          # Faster path when business may have records from user owned repositories
          if include_emus
            org_query = stats_query_segment_by_owner_type(owner_type: "ORGANIZATION", owners: organizations, feature_type:, visible_repo_ids:)
            user_query = stats_query_segment_by_owner_type(owner_type: "USER", owners: [], feature_type:, visible_repo_ids:)

            query_with_union = Arel.sql("#{org_query.to_sql} UNION ALL #{user_query.to_sql}")
            all_results = RepositorySecurityCenterConfig.connection.select_rows(query_with_union)

            # Here we have results for both orgs and users
            # We have to sum the org + user results by each feature_type
            results_by_feature_type = all_results.group_by { |row| row[0] }
            next results_by_feature_type.map do |feature_type, results|
              row1 = results.first
              if results.length == 1
                next {
                  feature_type: feature_type,
                  sum_scanning_count: row1[1],
                  affected_repo_count: row1[2],
                  total_critical: row1[3],
                  total_high: row1[4],
                  total_medium: row1[5],
                  total_moderate: row1[6],
                  total_low: row1[7],
                  total_error: row1[8],
                  total_warning: row1[9],
                  total_note: row1[10],
                }
              end

              row2 = results.second
              {
                feature_type: feature_type,
                sum_scanning_count: row1[1] + row2[1],
                affected_repo_count: row1[2] + row2[2],
                total_critical: row1[3] + row2[3],
                total_high: row1[4] + row2[4],
                total_medium: row1[5] + row2[5],
                total_moderate: row1[6] + row2[6],
                total_low: row1[7] + row2[7],
                total_error: row1[8] + row2[8],
                total_warning: row1[9] + row2[9],
                total_note: row1[10] + row2[10],
              }
            end
          end

          stats_query = stats_query_segment_by_owner_type(
            owner_type: "ORGANIZATION", owners: organizations,
            feature_type:, visible_repo_ids:)
          stats_query.map do |row|
            # project to a hash for easier consumption
            {
              feature_type: row.feature_type,
              sum_scanning_count: row.sum_scanning_count,
              affected_repo_count: row.affected_repo_count,
              total_critical: row.total_critical,
              total_high: row.total_high,
              total_medium: row.total_medium,
              total_moderate: row.total_moderate,
              total_low: row.total_low,
              total_error: row.total_error,
              total_warning: row.total_warning,
              total_note: row.total_note,
            }
          end
        end

        stats = log_timing(step: "build stats models") do
          stats_records.map do |row|
            counts_by_severity = {}
            total_alert_count = 0

            case row[:feature_type]
            when "dependabot_alerts"
              counts_by_severity[:critical] = row[:total_critical]&.to_i
              counts_by_severity[:high] = row[:total_high]&.to_i
              counts_by_severity[:moderate] = row[:total_moderate]&.to_i
              counts_by_severity[:low] = row[:total_low]&.to_i
              total_alert_count = counts_by_severity.values.sum

            when "code_scanning"
              counts_by_severity[:critical] = row[:total_critical]&.to_i
              counts_by_severity[:high] = row[:total_high]&.to_i
              counts_by_severity[:medium] = row[:total_medium]&.to_i
              counts_by_severity[:low] = row[:total_low]&.to_i
              counts_by_severity[:informational] ||= 0
              counts_by_severity[:informational] += row[:total_error]&.to_i
              counts_by_severity[:informational] += row[:total_warning]&.to_i
              counts_by_severity[:informational] += row[:total_note]&.to_i
              total_alert_count = counts_by_severity.values.sum

            when "secret_scanning"
              # we currently show secret scanning as just "alerts" - no explicit severity
              total_alert_count = row[:sum_scanning_count]&.to_i || 0
            end

            # remove any zero-value severities
            counts_by_severity.delete_if { |_, v| v.nil? || v.zero? }
            Stat.new(
              feature_type: feature_type || row[:feature_type]&.to_sym,
              affected_repo_count: row[:affected_repo_count]&.to_i || 0,
              total_repo_count: total_repo_count || 0,
              open_alerts_count: total_alert_count || 0,
              open_alerts_by_severity: counts_by_severity,
            )
          end
        end

        # when filtering on scanning_status = enabled, not all feature types may be returned
        # so we need to fill in any missing feature types
        if feature_type
          stats.push(Stat.new(
            feature_type: feature_type,
            total_repo_count: total_repo_count,
          )) if stats.length == 0
        else
          visible_features.each do |feature|
            if stats.none? { |s| s.feature_type == feature }
              stats.push(Stat.new(
                feature_type: feature,
                total_repo_count: total_repo_count,
              ))
            end
          end
        end

        stats
      end

      sig { params(feature_type: Symbol).returns(Stat) }
      def empty_stats(feature_type)
        Stat.new(
          feature_type:,
        )
      end

      sig { returns(T::Array[Symbol]) }
      memoize def visible_features
        SecurityFeatures.visible_features(scope).map(&:to_sym)
      end

      sig { returns(T::Array[T.untyped]) }
      memoize def filters
        filters_list = T.let([
          ::SecurityCenter::Filters::ByRepository.new(*@parser.values_without_qualifiers, substring_match: true, scope: scope),
          ::SecurityCenter::Filters::ByRepository.new(*@parser.values_for_qualifier(RiskQueryParser::REPOSITORY), scope: scope),
          ::SecurityCenter::Filters::ByVisibility.new(*@parser.values_for_qualifier(RiskQueryParser::VISIBILITY)),
          ::SecurityCenter::Filters::ByArchived.new(*@parser.values_for_qualifier(RiskQueryParser::ARCHIVED)),
          ::SecurityCenter::Filters::ByTeam.new(*@parser.values_for_qualifier(RiskQueryParser::TEAM), organizations: organizations, user: current_user),
          ::SecurityCenter::Filters::ByTopic.new(*@parser.values_for_qualifier(RiskQueryParser::TOPIC), organizations: organizations),
          ::SecurityCenter::Filters::ByFeature.new(*@parser.values_for_qualifier(RiskQueryParser::CODE_SCANNING), feature: :code_scanning, scope: scope),
          ::SecurityCenter::Filters::ByFeature.new(*@parser.values_for_qualifier(RiskQueryParser::DEPENDABOT_ALERTS), feature: :dependabot_alerts, scope: scope),
          ::SecurityCenter::Filters::ByFeature.new(*@parser.values_for_qualifier(RiskQueryParser::SECRET_SCANNING), feature: :secret_scanning, scope: scope),
          ::SecurityCenter::Filters::ByHasSeverity.new(*@parser.values_for_qualifier(RiskQueryParser::HAS_SEVERITY)),
        ], T::Array[T.untyped])

        additional_filters_list =
          if scope.is_a?(Business)
            [
              ::SecurityCenter::Filters::ByOwner.new(*parser.values_for_qualifier(RiskQueryParser::OWNER), T.cast(scope, Business)),
              ::SecurityCenter::Filters::ByOwnerType.new(*parser.values_for_qualifier(RiskQueryParser::OWNER_TYPE), T.cast(scope, Business)),
            ]
          else
            [::SecurityCenter::Filters::ByCustomProperty.new(
              allowed_repo_ids: repo_ids_by_feature&.values&.flatten&.uniq,
              org: T.cast(scope, ::Organization),
              query: parser.custom_properties_query_string,
              user: current_user,
              user_session: user_session
            )]
          end

        filters_list.concat(additional_filters_list)
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

      sig { returns(T::Boolean) }
      memoize def has_by_feature_filter?
        filters.any? do |filter|
          filter.is_a?(::SecurityCenter::Filters::ByFeature) && !filter.is_empty?
        end
      end

      sig { params(owner_type: String, owners: T::Array[Organization], feature_type: T.nilable(Symbol), visible_repo_ids: T.nilable(T::Array[Integer])).returns(ActiveRecord::Relation) }
      def stats_query_segment_by_owner_type(owner_type:, owners:, feature_type:, visible_repo_ids:)
        base_query = RepositorySecurityCenterConfig.none
        if owner_type == "ORGANIZATION"
          biz = @scope.is_a?(Business) ? @scope : @scope.business
          base_query = RepositorySecurityCenterConfig
            .with_owners_under_business(biz, owners, include_emus: false)
        elsif owner_type == "USER"
          return RepositorySecurityCenterConfig.none unless emus_in_scope?

          base_query = RepositorySecurityCenterConfig.where(business: @scope, owner_type: "USER")
        else
          return RepositorySecurityCenterConfig.none
        end

        status_query_params = {
          # We're limiting to a single feature (for non-admin users), or to all available features
          # This implicitly excludes status/counts for non-primary features (e.g. push protection)
          feature_type: feature_type || visible_features,
          # "Affected" stats only reflect repos where feature is enabled
          # Filtering to enrolled improves performance when features aren't enabled on the entire org
          scanning_status: :enrolled,
          # "Affected" stats only reflect repos where feature has active alerts
          scanning_count: 1..,
        }

        if scope.is_a?(Business)
          status_query_params[:business_id] = scope.id
        end

        statuses_table_index_optimization = if scope.is_a?(Business) && owner_type == "ORGANIZATION" && !has_by_feature_filter?
          # Apply index hint on inner join where statses table is used as left table to prevent MySQL from using index_on_owner_id_feature_type_repository_id instead.
          # This is not necessary when by feature filter presents where subquery will likely be the left table for nested loop.
          " USE INDEX (index_owner_id_feature_scanning_status_scanning_count_repo_id)"
        else
          ""
        end

        RepositorySecurityCenterConfig
          .joins(%{
            INNER JOIN repository_security_center_statuses#{statuses_table_index_optimization}
              ON repository_security_center_statuses.owner_id = repository_security_center_configs.owner_id
              AND repository_security_center_statuses.repository_id = repository_security_center_configs.repository_id
          })
          .joins(%{
            LEFT JOIN security_center_alert_severities
              ON security_center_alert_severities.repository_id = repository_security_center_statuses.repository_id
              AND security_center_alert_severities.feature_type = repository_security_center_statuses.feature_type
          })
          .then do |rel|
            rel.and(base_query)
          end
          .where(repository_security_center_statuses: status_query_params)
          .then do |rel|
            next rel if visible_repo_ids.nil?
            rel.where(repository_id: visible_repo_ids)
          end
          .then { |rel| filters.reduce(rel) { |r, filter| filter.apply(r) } }
          .group("repository_security_center_statuses.feature_type")
          .select(
            "repository_security_center_statuses.feature_type",
            Arel.sql("SUM(repository_security_center_statuses.scanning_count) as sum_scanning_count"),
            Arel.sql("COUNT(DISTINCT repository_security_center_statuses.repository_id) as affected_repo_count"),
            Arel.sql("SUM(IF(security_center_alert_severities.severity = 'critical', security_center_alert_severities.alert_count, 0)) as total_critical"),
            Arel.sql("SUM(IF(security_center_alert_severities.severity = 'high', security_center_alert_severities.alert_count, 0)) as total_high"),
            Arel.sql("SUM(IF(security_center_alert_severities.severity = 'medium', security_center_alert_severities.alert_count, 0)) as total_medium"),
            Arel.sql("SUM(IF(security_center_alert_severities.severity = 'moderate', security_center_alert_severities.alert_count, 0)) as total_moderate"),
            Arel.sql("SUM(IF(security_center_alert_severities.severity = 'low', security_center_alert_severities.alert_count, 0)) as total_low"),
            Arel.sql("SUM(IF(security_center_alert_severities.severity = 'error', security_center_alert_severities.alert_count, 0)) as total_error"),
            Arel.sql("SUM(IF(security_center_alert_severities.severity = 'warning', security_center_alert_severities.alert_count, 0)) as total_warning"),
            Arel.sql("SUM(IF(security_center_alert_severities.severity = 'note', security_center_alert_severities.alert_count, 0)) as total_note"),
            Arel.sql("? AS owner_type", owner_type),
          )
      end

      sig { returns(T::Boolean) }
      memoize def emus_in_scope?
        scope.is_a?(Business) && SecurityProduct::Permissions::BusinessAuthz.new(T.cast(scope, Business), actor: current_user).can_view_user_owned_repository_alerts?
      end
    end
  end
end
