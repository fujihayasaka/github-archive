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
              authorized_orgs_by_feature: T.nilable(T::Hash[Symbol, T::Array[Organization]]),
              user_session: ::UserSession,
              is_open_selected: T::Boolean,
            ).void
          end
          def initialize(user:, query_parser:, alerts_filterer:, repos_filterer:, scope:, start_date:, end_date:, security_features:, authorized_orgs_by_feature:, user_session:, is_open_selected:)
            super(
              user:,
              query_parser:,
              alerts_filterer:,
              repos_filterer:,
              scope:,
              start_date:,
              end_date:,
              security_features: security_features & [::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS],
              authorized_orgs_by_feature:,
              user_session:,
              is_open_selected:,
            )
          end

          private

          sig { override.returns(RunQueryOutput) }
          def query
            if run_sliced_queries?
              # Run the query in parallel for each advisory_slice4
              # Then re-order by open_alerts and take the first 10 advisories
              # Note that same advisory can not get into multiple slices by definition, so rows are unique
              # The slice4 is calculated as crc of the ghsa_id, which is a stable function,
              # and so same advisory will always get into the same slice
              (0..3).map do |advisory_slice4|
                sql = %{
                  SELECT
                    COUNT(*) AS open_alerts,
                    rev.ghsa_id
                  FROM (#{union_all_sql(slice_by: SliceBy.new(value_4_slices: advisory_slice4, dimension: :by_advisory))}) AS rev
                  GROUP BY rev.ghsa_id
                  ORDER BY open_alerts DESC, rev.ghsa_id ASC
                  LIMIT 10
                }.squish

                ApplicationRecord::SecurityOverviewAnalytics.connection.select_all(sql, async: true)
              end
              # Async queries return above end up returning array of promise-like ActiveRecord::FutureResult objects
              # The objects have .then method which return completed promises with values
              .map { |promise| promise.then(&:rows) }
              .flat_map(&:value)
              .sort_by { |row| [-row[0], row[1]] }
              .first(10)
              .map do |row|
                {
                  ghsa_id: row[1],
                  open_alerts: row[0].to_i
                }
              end
            else
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
