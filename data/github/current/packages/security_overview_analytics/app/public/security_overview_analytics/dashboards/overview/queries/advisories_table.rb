# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AdvisoriesTable < Base
          RunQueryOutput = type_member { { fixed: T::Array[T::Hash[T.untyped, T.untyped]] } }

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
            super(
              user:,
              query_parser:,
              alerts_filterer:,
              repos_filterer:,
              scope:,
              start_date:,
              end_date:,
              security_features: security_features & [::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS],
              authorized_orgs:,
              user_session:,
              return_alert_count: false, # No query parallelization as this data comes from a single table.
              is_open_selected:,
            )
          end

          private

          sig { override.returns(RunQueryOutput) }
          def query
            sql = %{
              SELECT
                COUNT(*) AS open_alerts,
                rev.ghsa_id
              FROM (#{union_all_sql}) AS rev
              GROUP BY rev.ghsa_id
              ORDER BY open_alerts DESC, rev.ghsa_id ASC
              LIMIT 10
            }.squish

            ApplicationRecord::SecurityOverviewAnalytics.connection.select_all(sql).map do |row|
              {
                ghsa_id: row.fetch("ghsa_id"),
                open_alerts: row.fetch("open_alerts").to_i
              }
            end
          end

          sig { override.returns(String) }
          def union_all_fallback_sql
            %{
              SELECT NULL AS ghsa_id
              WHERE FALSE
            }.squish
          end

          sig do
            override.params(
              rel: ActiveRecord::Relation,
              repo_metadata_rel: ActiveRecord::Relation,
              table_name: String
            ).returns(ActiveRecord::Relation)
          end
          def common_clauses_rel(rel, repo_metadata_rel, table_name)
            rel
              .where(alert_resolved: false, repository_id: repo_metadata_rel.select(:repository_id))
              .where("next_revision_date_id > ?", end_date_id)
              .where("date_id <= ?", end_date_id)
          end
        end
      end
    end
  end
end
