# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"
require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alert_lifecycle_event_pb"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class Base
          extend T::Sig
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

          sig { returns(T::Boolean) }
          attr_reader :return_alert_count

          sig { returns(T.nilable(T::Array[::Organization])) }
          attr_reader :authorized_orgs

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
              return_alert_count: T::Boolean,
              is_open_selected: T::Boolean,
              slice4: T.nilable(Integer),
            ).returns(T.attached_class)
          end
          def self.for_organization(organization:, user:, query:, start_date:, end_date:, user_session:, return_alert_count: false, is_open_selected: true, slice4: nil)
            alerts_filterer = ::SecurityOverviewAnalytics::Dashboards::AlertsFilterer.new(
              query:,
              scope: organization,
              user: user,
              slice4:,
            )

            if SecurityProduct::Permissions::OrgAuthz.new(organization, actor: user).can_manage_security_products?
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

            security_features_parser = ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser.new(
              query:,
              scope: organization,
              allowed_code_scanning_repo_ids:,
            )

            security_features = security_features_parser.selected_backend_security_features

            repos_filterer = ::SecurityOverviewAnalytics::Dashboards::OrgReposFilterer.new(
              allowed_repo_ids_by_feature:,
              organization:,
              query:,
              user:,
              user_session:
            )

            new(user:, query_parser: query, alerts_filterer:, repos_filterer:, scope: organization, start_date:, end_date:, security_features:, authorized_orgs: nil, user_session:, return_alert_count:, is_open_selected:,)
          end

          sig do
            params(
              business: Business,
              user: User,
              query: ::Search::Queries::SecurityCenter::QueryParser,
              start_date: ::Date,
              end_date: ::Date,
              authorized_orgs: T::Array[Organization],
              user_session: UserSession,
              return_alert_count: T::Boolean,
              is_open_selected: T::Boolean,
              slice4: T.nilable(Integer),
            ).returns(T.attached_class)
          end
          def self.for_business(business:, user:, query:, start_date:, end_date:, authorized_orgs:, user_session:, return_alert_count: false, is_open_selected: true, slice4: nil)
            alerts_filterer = ::SecurityOverviewAnalytics::Dashboards::AlertsFilterer.new(
              query:,
              scope: business,
              user:,
              slice4: slice4
            )

            security_features_parser = ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser.new(
              query:,
              scope: business,
              authorized_orgs:,
            )

            security_features = security_features_parser.selected_backend_security_features

            repos_filterer = ::SecurityOverviewAnalytics::Dashboards::EnterpriseReposFilterer.new(
              business:,
              organizations: authorized_orgs,
              query:,
              user:
            )

            new(user:, query_parser: query, alerts_filterer:, repos_filterer:, scope: business, start_date:, end_date:, security_features:, authorized_orgs:, user_session:, return_alert_count:, is_open_selected:,)
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
              authorized_orgs: T.nilable(T::Array[Organization]),
              user_session: ::UserSession,
              return_alert_count: T::Boolean,
              is_open_selected: T::Boolean,
            ).void
          end
          def initialize(user:, query_parser:, alerts_filterer:, repos_filterer:, scope:, start_date:, end_date:, security_features:, authorized_orgs:, user_session:, return_alert_count:, is_open_selected:)
            @alerts_filterer = alerts_filterer
            @repos_filterer = repos_filterer
            @scope = scope
            @user = user
            @query_parser = query_parser
            @start_date = start_date
            @end_date = end_date
            @security_features = T.let(security_features.to_set, T::Set[String])
            @authorized_orgs = authorized_orgs
            @user_session = user_session
            @return_alert_count = return_alert_count
            @is_open_selected = is_open_selected
          end

          sig { overridable.returns(RunQueryOutput) }
          def perform
            GitHub.dogstats.distribution_time("security_overview_analytics.dashboards.overview.#{T.must(self.class.name).underscore}.perform.dist") do
              query
            end
          end

          private

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

          sig { overridable.params(slice4: T.nilable(Integer)).returns(String) }
          def union_all_sql(slice4: nil)
            query_parts = []
            query_parts << "(#{code_scanning_rel(slice4:).to_sql})" if include_code_scanning?
            query_parts << "(#{dependabot_alerts_rel(slice4:).to_sql})" if include_dependabot_alerts?
            query_parts << "(#{secret_scanning_rel(slice4:).to_sql})" if include_secret_scanning?

            return query_parts.join(" UNION ALL ") if query_parts.any?

            union_all_fallback_sql
          end

          # The query for code scanning alert revisions.
          sig { overridable.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
          def code_scanning_rel(slice4: nil)
            rel = alerts_filterer.cs_alert_rel(security_features)
            common_clauses_rel(rel, repo_metadata_rels(slice4:).fetch(::SecurityCenter::SecurityFeatures::CODE_SCANNING), CS_TABLE_NAME)
          end

          # The query for Dependabot alert revisions.
          sig { overridable.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
          def dependabot_alerts_rel(slice4: nil)
            rel = alerts_filterer.dbot_alert_rel
            common_clauses_rel(rel, repo_metadata_rels(slice4:).fetch(::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS), DBOT_TABLE_NAME)
          end

          # The query for secret scanning alert revisions.
          sig { overridable.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
          def secret_scanning_rel(slice4: nil)
            rel = alerts_filterer.ss_alert_rel
            common_clauses_rel(rel, repo_metadata_rels(slice4:).fetch(::SecurityCenter::SecurityFeatures::SECRET_SCANNING), SS_TABLE_NAME)
          end

          # A mapping from security feature names to repo metadata relations representing repositories that currently have the feature enabled.
          sig { params(slice4: T.nilable(Integer)).returns(T::Hash[String, ActiveRecord::Relation]) }
          def repo_metadata_rels(slice4: nil)
            if slice4.nil?
              return T.must(@_repo_metadata_rels) if defined?(@_repo_metadata_rels)
            elsif defined?(@_repo_metadata_sliced_rels)
              sliced_rels = T.must(@_repo_metadata_sliced_rels)
              return T.must(sliced_rels[slice4]) if sliced_rels[slice4].present?
            end

            rels = T.let({}, T::Hash[String, ActiveRecord::Relation])

            # A repo metadata relation representing repositories that have code scanning currently enabled.
            rels[::SecurityCenter::SecurityFeatures::CODE_SCANNING] =
              repos_filterer
                .cs_repo_metadata_rel(slice4:)
                .joins(:feature_status_revisions)
                .where(feature_status_revisions: { next_revision_date_id: ::SecurityOverviewAnalytics::Date::FUTURE_DATE_ID })
                .where(feature_status_revisions: { code_scanning_enabled: true })

            # A repo metadata relation representing repositories that have dependabot alerts currently enabled.
            rels[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS] =
              repos_filterer
                .dbot_repo_metadata_rel(slice4:)
                .joins(:feature_status_revisions)
                .where(feature_status_revisions: { next_revision_date_id: ::SecurityOverviewAnalytics::Date::FUTURE_DATE_ID })
                .where(feature_status_revisions: { dependabot_alerts_enabled: true })

            # A repo metadata relation representing repositories that have secret scanning currently enabled.
            rels[::SecurityCenter::SecurityFeatures::SECRET_SCANNING] =
              repos_filterer
                .ss_repo_metadata_rel(slice4:)
                .joins(:feature_status_revisions)
                .where(feature_status_revisions: { next_revision_date_id: ::SecurityOverviewAnalytics::Date::FUTURE_DATE_ID })
                .where(feature_status_revisions: { secret_scanning_enabled: true })

            # manually memorize rels based on slice4 input
            if slice4.nil?
              @_repo_metadata_rels = T.let(rels, T.nilable(T::Hash[String, ActiveRecord::Relation]))
            else
              @_repo_metadata_sliced_rels ||= T.let({}, T.nilable(T::Hash[Integer, T::Hash[String, ActiveRecord::Relation]]))
              @_repo_metadata_sliced_rels[slice4] = rels
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
