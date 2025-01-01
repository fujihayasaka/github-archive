# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"
require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alert_lifecycle_event_pb"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class Base
          extend T::Helpers
          extend T::Generic
          include GitHub::Memoizer
          include GitHub::SecurityCenter::LoggingHelper

          abstract!

          RunQueryOutputAlias = T.type_alias { T.untyped }
          RunQueryOutput = type_member { { fixed: RunQueryOutputAlias } }

          RESOLUTIONS_CODE_SCANNING = ::Turboscan::Proto::ResultResolution
          RESOLUTIONS_DEPENDABOT_ALERTS = ::Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertLifecycleEvent::LastStateChangeReason
          RESOLUTIONS_SECRET_SCANNING = ::GitHub::Proto::SecretScanning::Types::V1::TokenResolution

          CS_TABLE_NAME = T.let(CodeScanningAlertRevision.table_name, String)
          SS_TABLE_NAME = T.let(SecretScanningAlertRevision.table_name, String)
          DBOT_TABLE_NAME = T.let(DependabotAlertRevision.table_name, String)

          sig { returns(::SecurityOverviewAnalytics::Dashboards::AlertsFilterer) }
          attr_reader :alerts_filterer

          sig { returns(::SecurityOverviewAnalytics::Dashboards::ReposFilterer) }
          attr_reader :repos_filterer

          sig { returns(T.any(::Organization, ::Business)) }
          attr_reader :scope

          sig { returns(::User) }
          attr_reader :user

          sig { returns(::Search::Queries::SecurityCenter::QueryParser) }
          attr_reader :query_parser

          sig { returns(::UserSession) }
          attr_reader :user_session

          sig { returns(::Date) }
          attr_reader :start_date, :end_date

          sig { returns(T::Set[String]) }
          attr_reader :security_features

          sig { returns(T.nilable(T::Hash[Symbol, T::Array[Organization]])) }
          attr_reader :authorized_orgs_by_feature

          sig { returns(T::Boolean) }
          attr_reader :is_open_selected

          sig do
            params(
              organization: Organization,
              user: User,
              query: ::Search::Queries::SecurityCenter::QueryParser,
              start_date: ::Date,
              end_date: ::Date,
              user_session: UserSession,
              security_features: T.nilable(T::Array[String]),
              is_open_selected: T::Boolean,
            ).returns(T.attached_class)
          end
          def self.for_organization(organization:, user:, query:, start_date:, end_date:, user_session:, security_features: nil, is_open_selected: true)
            alerts_filterer = ::SecurityOverviewAnalytics::Dashboards::AlertsFilterer.new(
              query:,
              scope: organization,
              user: user,
            )

            org_authz = SecurityProduct::Permissions::OrgAuthz.new(organization, actor: user)

            can_view_all_alerts = if SecurityCenter::FeatureFlagHelper.allow_custom_role_view_all_permission_check?(user, organization)
              org_authz.can_view_all_alerts?
            else
              org_authz.can_manage_security_products?
            end

            if can_view_all_alerts
              allowed_repo_ids_by_feature = nil
              allowed_code_scanning_repo_ids = nil
            else
              allowed_repository_ids_by_feature_for_organization_members = SecurityCenter::AuthorizationEnumerator.new(
                user:,
                org: organization,
                datadog_tags: ["controller:overview_dashboard", "action:overview_base", "scope:organization"]
              ).allowed_repository_ids_by_feature_for_organization_member

              allowed_repo_ids_by_feature = allowed_repository_ids_by_feature_for_organization_members.transform_values(&:first)
              allowed_code_scanning_repo_ids = allowed_repository_ids_by_feature_for_organization_members[::SecurityCenter::SecurityFeatures::CODE_SCANNING]&.first
            end

            if security_features.nil?
              security_features_parser = ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser.new(
                query:,
                scope: organization,
                allowed_code_scanning_repo_ids:,
              )

              security_features = security_features_parser.selected_backend_security_features
            end

            repos_filterer = ::SecurityOverviewAnalytics::Dashboards::OrgReposFilterer.new(
              allowed_repo_ids_by_feature:,
              organization:,
              query:,
              user:,
              user_session:
            )

            new(user:, query_parser: query, alerts_filterer:, repos_filterer:, scope: organization, start_date:, end_date:, security_features:, authorized_orgs_by_feature: nil, user_session:, is_open_selected:)
          end

          sig do
            params(
              business: Business,
              user: User,
              query: ::Search::Queries::SecurityCenter::QueryParser,
              start_date: ::Date,
              end_date: ::Date,
              authorized_orgs_by_feature: T::Hash[Symbol, T::Array[Organization]],
              user_session: UserSession,
              security_features: T.nilable(T::Array[String]),
              is_open_selected: T::Boolean,
            ).returns(T.attached_class)
          end
          def self.for_business(business:, user:, query:, start_date:, end_date:, authorized_orgs_by_feature:, user_session:, security_features: nil, is_open_selected: true)
            alerts_filterer = ::SecurityOverviewAnalytics::Dashboards::AlertsFilterer.new(
              query:,
              scope: business,
              user:,
            )

            if security_features.nil?
              security_features_parser = ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser.new(
                query:,
                scope: business,
                authorized_code_scanning_orgs: T.must(authorized_orgs_by_feature[:code_scanning]),
              )

              security_features = security_features_parser.selected_backend_security_features
            end

            repos_filterer = ::SecurityOverviewAnalytics::Dashboards::EnterpriseReposFilterer.new(
              business:,
              organizations: authorized_orgs_by_feature,
              query:,
              user:
            )

            new(user:, query_parser: query, alerts_filterer:, repos_filterer:, scope: business, start_date:, end_date:, security_features:, authorized_orgs_by_feature:, user_session:, is_open_selected:)
          end

          sig do
            params(
              user: User,
              query_parser: ::Search::Queries::SecurityCenter::QueryParser,
              alerts_filterer: ::SecurityOverviewAnalytics::Dashboards::AlertsFilterer,
              repos_filterer: ::SecurityOverviewAnalytics::Dashboards::ReposFilterer,
              scope: T.any(::Organization, ::Business),
              start_date: ::Date,
              end_date: ::Date,
              security_features: T::Array[String],
              authorized_orgs_by_feature: T.nilable(T::Hash[Symbol, T::Array[Organization]]),
              user_session: ::UserSession,
              is_open_selected: T::Boolean,
            ).void
          end
          def initialize(user:, query_parser:, alerts_filterer:, repos_filterer:, scope:, start_date:, end_date:, security_features:, authorized_orgs_by_feature:, user_session:, is_open_selected:)
            @alerts_filterer = alerts_filterer
            @repos_filterer = repos_filterer
            @scope = scope
            @user = user
            @query_parser = query_parser
            @start_date = start_date
            @end_date = end_date
            @security_features = T.let(security_features.to_set, T::Set[String])
            @authorized_orgs_by_feature = authorized_orgs_by_feature
            @user_session = user_session
            @is_open_selected = is_open_selected
          end

          sig { overridable.returns(RunQueryOutput) }
          def perform
            GitHub.dogstats.distribution_time("security_overview_analytics.dashboards.overview.#{T.must(self.class.name).underscore}.perform.dist", tags: ["scope:#{scope.class.name&.downcase}"]) do
              query
            end
          end

          class SliceBy < T::Struct
            DIMENSIONS = [:by_repository, :by_alert_revision, :by_advisory, :by_rule].freeze

            prop :value_4_slices, Integer
            prop :dimension, Symbol

            sig { params(value_4_slices: Integer, dimension: Symbol).void }
            def initialize(value_4_slices:, dimension:)
              raise ArgumentError, "Invalid dimension" unless DIMENSIONS.include?(dimension)

              super
            end
          end

          private

          ###
          # Abstracts the async bits of running the sql query
          #
          # @param accumulator custom accumulator to pass to results_reducer
          # @param results_reducer The callback to reduce the results from several async queries into one result
          # @param block The callback to get the sql query string. This gets passed the union_all_sql string, and returns full query
          # @return accumulator
          sig do type_parameters(:R)
            .params(
              results_reducer: T.proc.params(accumulator: T.type_parameter(:R), slice_result: T::Hash[String, T.untyped]).returns(T.type_parameter(:R)),
              accumulator: T.type_parameter(:R),
              block: T.proc.params(union_all_sql_string: String).returns(String),
            ).returns(T.type_parameter(:R))
          end
          def run_sliced_alert_revisions_query(results_reducer:, accumulator:, &block)
            if run_sliced_queries?
              results = (0..3).map do |alert_revisions_slice4|
                sql = yield(union_all_sql(slice_by: SliceBy.new(value_4_slices: alert_revisions_slice4, dimension: :by_alert_revision)))
                ApplicationRecord::SecurityOverviewAnalytics.connection.select_all(sql, async: true)
              end
              reduce_async_results(results:, results_reducer:, accumulator:)
            else
              sql = yield(union_all_sql)
              results = [ApplicationRecord::SecurityOverviewAnalytics.connection.select_all(sql)]
              reduce_results(results:, results_reducer:, accumulator:)
            end
          end

          ###
          # Abstracts the async bits of running the relationship query
          #
          # @param accumulator custom accumulator to pass to results_reducer
          # @param results_reducer The callback to reduce the results from several async queries into one result
          # @return accumulator
          sig do type_parameters(:R)
            .params(
              relation: ActiveRecord::Relation,
              results_reducer: T.proc.params(accumulator: T.type_parameter(:R), slice_result: T::Hash[String, T.untyped]).returns(T.type_parameter(:R)),
              accumulator: T.type_parameter(:R),
            ).returns(T.type_parameter(:R))
          end
          def run_sliced_alert_revisions_rel(relation:, results_reducer:, accumulator:)
            if run_sliced_queries?
              results = (0..3).map do |alert_revisions_slice4|
                relation.where(slice4: alert_revisions_slice4).load_async
              end
              reduce_async_results(results:, results_reducer:, accumulator:)
            else
              results = [relation.load]
              reduce_results(results:, results_reducer:, accumulator:)
            end
          end

          ### Run sliced queries on non-GHES environments. On GHES, do not run sliced queries or parallelize, as there is no read replicas.
          sig { returns(T::Boolean) }
          def run_sliced_queries?
            !GitHub.enterprise?
          end

          sig do type_parameters(:R)
            .params(
              results: T::Array[ActiveRecord::FutureResult],
              results_reducer: T.proc.params(accumulator: T.type_parameter(:R), slice_result: T::Hash[String, T.untyped]).returns(T.type_parameter(:R)),
              accumulator: T.type_parameter(:R),
            ).returns(T.type_parameter(:R))
          end
          def reduce_async_results(results:, results_reducer:, accumulator:)
            # Async queries above end up returning array of promise-like ActiveRecord::FutureResult objects
            # The objects have .then method which return completed promises with values
            results = results.map { |promise| promise.then { |result| result } }

            # Empty results don't have value property
            results = results.map { |result| result.respond_to?(:value) ? result.value : nil }.compact

            reduce_results(results:, results_reducer:, accumulator:)
          end

          sig do type_parameters(:R)
            .params(
              results: T::Array[ActiveRecord::Result],
              results_reducer: T.proc.params(accumulator: T.type_parameter(:R), slice_result: T::Hash[String, T.untyped]).returns(T.type_parameter(:R)),
              accumulator: T.type_parameter(:R),
            ).returns(T.type_parameter(:R))
          end
          def reduce_results(results:, results_reducer:, accumulator:)
            results = results.flat_map { |result| T.cast(result.to_a, T::Array[T::Hash[String, T.untyped]]) }

            result = results.reduce(accumulator) do |accumulator, slice_result|
              results_reducer.call(accumulator, slice_result)
            end
          end

          class SingleValueAccumulator < T::Struct
            prop :value, Float, default: 0.0
            prop :alert_count, Integer, default: 0

            sig { params(value: Float, alert_count: Integer).void }
            def initialize(value: 0.0, alert_count: 0)
              super
            end
          end

          sig do type_parameters(:R)
            .params(data_column: Symbol, count_column: Symbol)
            .returns(
              T.proc.params(accumulator: SingleValueAccumulator, slice_result: T::Hash[String, T.untyped]).returns(T.type_parameter(:R))
            )
          end
          def avg_reducer(data_column:, count_column:)
            ->(accumulator, slice_result) {
              return accumulator if slice_result[count_column.to_s] == 0

              slice_alert_count = (slice_result[count_column.to_s] || 0).round
              slice_value = (slice_result[data_column.to_s] || 0).to_f

              total_alerts = accumulator.alert_count + slice_alert_count
              total_value = accumulator.value * accumulator.alert_count + slice_value * slice_alert_count
              accumulator.value = total_value / total_alerts
              accumulator.alert_count = total_alerts
              accumulator
            }
          end

          sig do type_parameters(:R)
            .params(count_column: Symbol)
            .returns(
              T.proc.params(accumulator: SingleValueAccumulator, slice_result: T::Hash[String, T.untyped]).returns(T.type_parameter(:R))
            )
          end
          def count_reducer(count_column:)
            ->(accumulator, slice_result) {
              return accumulator if slice_result[count_column.to_s] == 0

              slice_alert_count = (slice_result[count_column.to_s] || 0).round
              total_alerts = accumulator.alert_count + slice_alert_count

              accumulator.alert_count = total_alerts
              accumulator
            }
          end

          # Build and execute the query.
          sig { abstract.returns(RunQueryOutput) }
          def query; end

          # A SQL query that will result in an empty tabular value, with columns matching
          # the same columns `union_all_sql` generates.
          #
          # If no security features are selected, then `union_all_sql` falls back to this method.
          sig { abstract.returns(String) }
          def union_all_fallback_sql; end

          # The SOA revisions tables have many columns that are the same in each table, e.g. date_id, next_revision_date_id, and repository_id.
          # There are filters we typically want to apply that are the same for each revisions table.
          # Set those conditions here.
          #
          # Example:
          #
          #   sig { override… }
          #   def common_clauses_rel(rel, repo_metadata_rel)
          #     rel
          #       .where(alert_resolved: false, repository_id: repo_metadata_rel.select(:repository_id))
          #       .where("next_revision_date_id > ?", end_date_id)
          #       .where("date_id <= ?", end_date_id)
          #   end
          sig do
            abstract.params(
              rel: ActiveRecord::Relation,
              repo_metadata_rel: ActiveRecord::Relation,
              table_name: String
            ).returns(ActiveRecord::Relation)
          end
          def common_clauses_rel(rel, repo_metadata_rel, table_name); end

          sig { overridable.params(slice_by: T.nilable(SliceBy)).returns(String) }
          def union_all_sql(slice_by: nil)
            query_parts = []
            query_parts << "(#{code_scanning_rel(slice_by:).to_sql})" if include_code_scanning?
            query_parts << "(#{dependabot_alerts_rel(slice_by:).to_sql})" if include_dependabot_alerts?
            query_parts << "(#{secret_scanning_rel(slice_by:).to_sql})" if include_secret_scanning?

            return query_parts.join(" UNION ALL ") if query_parts.any?

            union_all_fallback_sql
          end

          # The query for code scanning alert revisions.
          sig { overridable.params(slice_by: T.nilable(SliceBy)).returns(ActiveRecord::Relation) }
          def code_scanning_rel(slice_by: nil)
            rel = alerts_filterer.cs_alert_rel(security_features:, slice_by:)
            common_clauses_rel(rel, repo_metadata_rels(slice_by:).fetch(::SecurityCenter::SecurityFeatures::CODE_SCANNING), CS_TABLE_NAME)
          end

          # The query for Dependabot alert revisions.
          sig { overridable.params(slice_by: T.nilable(SliceBy)).returns(ActiveRecord::Relation) }
          def dependabot_alerts_rel(slice_by: nil)
            rel = alerts_filterer.dbot_alert_rel(slice_by:)
            common_clauses_rel(rel, repo_metadata_rels(slice_by:).fetch(::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS), DBOT_TABLE_NAME)
          end

          # The query for secret scanning alert revisions.
          sig { overridable.params(slice_by: T.nilable(SliceBy)).returns(ActiveRecord::Relation) }
          def secret_scanning_rel(slice_by: nil)
            rel = alerts_filterer.ss_alert_rel(slice_by:)
            common_clauses_rel(rel, repo_metadata_rels(slice_by:).fetch(::SecurityCenter::SecurityFeatures::SECRET_SCANNING), SS_TABLE_NAME)
          end

          # A mapping from security feature names to repo metadata relations representing repositories that currently have the feature enabled.
          sig { params(slice_by: T.nilable(SliceBy)).returns(T::Hash[String, ActiveRecord::Relation]) }
          def repo_metadata_rels(slice_by: nil)
            repos_slice4 = slice_by.nil? || slice_by.dimension != :by_repository ? nil : slice_by.value_4_slices

            if repos_slice4.nil?
              return T.must(@_repo_metadata_rels) if defined?(@_repo_metadata_rels)
            elsif defined?(@_repo_metadata_sliced_rels)
              sliced_rels = T.must(@_repo_metadata_sliced_rels)
              return T.must(sliced_rels[repos_slice4]) if sliced_rels[repos_slice4].present?
            end

            rels = T.let({}, T::Hash[String, ActiveRecord::Relation])

            # A repo metadata relation representing repositories that have code scanning currently enabled.
            rels[::SecurityCenter::SecurityFeatures::CODE_SCANNING] =
              repos_filterer
                .cs_repo_metadata_rel(repos_slice4:)
                .joins(:feature_status_revisions)
                .where(feature_status_revisions: { next_revision_date_id: ::SecurityOverviewAnalytics::Date::FUTURE_DATE_ID })
                .where(feature_status_revisions: { code_scanning_enabled: true })

            # A repo metadata relation representing repositories that have dependabot alerts currently enabled.
            rels[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS] =
              repos_filterer
                .dbot_repo_metadata_rel(repos_slice4:)
                .joins(:feature_status_revisions)
                .where(feature_status_revisions: { next_revision_date_id: ::SecurityOverviewAnalytics::Date::FUTURE_DATE_ID })
                .where(feature_status_revisions: { dependabot_alerts_enabled: true })

            # A repo metadata relation representing repositories that have secret scanning currently enabled.
            rels[::SecurityCenter::SecurityFeatures::SECRET_SCANNING] =
              repos_filterer
                .ss_repo_metadata_rel(repos_slice4:)
                .joins(:feature_status_revisions)
                .where(feature_status_revisions: { next_revision_date_id: ::SecurityOverviewAnalytics::Date::FUTURE_DATE_ID })
                .where(feature_status_revisions: { secret_scanning_enabled: true })

            # manually memorize rels based on repos_slice4 input
            if repos_slice4.nil?
              @_repo_metadata_rels = T.let(rels, T.nilable(T::Hash[String, ActiveRecord::Relation]))
            else
              @_repo_metadata_sliced_rels ||= T.let({}, T.nilable(T::Hash[Integer, T::Hash[String, ActiveRecord::Relation]]))
              @_repo_metadata_sliced_rels[repos_slice4] = rels
            end

            rels
          end

          sig { returns(Integer) }
          memoize def start_date_id
            ::SecurityOverviewAnalytics::Date.id_from_date(start_date)
          end

          sig { returns(Integer) }
          memoize def end_date_id
            ::SecurityOverviewAnalytics::Date.id_from_date(end_date)
          end

          sig { returns(Integer) }
          memoize def day_after_end_date_id
            ::SecurityOverviewAnalytics::Date.id_from_date(end_date.next_day(1))
          end

          sig { params(convert_tz_val: T.any(Integer, String)).returns(String) }
          def convert_datetime_to_utc_sql(convert_tz_val)
            "convert_tz(#{convert_tz_val},'system','+00:00')"
          end

          sig { params(convert_tz_val: T.any(Integer, String)).returns(String) }
          def convert_utc_datetime_to_system_sql(convert_tz_val)
            "convert_tz(#{convert_tz_val},'+00:00','system')"
          end

          sig { returns(T::Boolean) }
          def include_code_scanning?
            code_scanning_features = security_features - [::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS, ::SecurityCenter::SecurityFeatures::SECRET_SCANNING]
            code_scanning_features.present?
          end

          sig { returns(T::Boolean) }
          def include_dependabot_alerts?
            security_features.include?(::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS)
          end

          sig { returns(T::Boolean) }
          def include_secret_scanning?
            security_features.include?(::SecurityCenter::SecurityFeatures::SECRET_SCANNING)
          end

          instrument_method \
            :code_scanning_rel,
            :dependabot_alerts_rel,
            :perform,
            :repo_metadata_rels,
            :secret_scanning_rel,
            :union_all_sql
        end
      end
    end
  end
end
