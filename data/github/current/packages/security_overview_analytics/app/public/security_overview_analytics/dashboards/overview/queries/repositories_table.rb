# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class RepositoriesTable < Base
          RunQueryOutput = type_member { { fixed: T::Array[T::Hash[T.untyped, T.untyped]] } }

          private

          sig { override.params(offset: T.nilable(Integer), limit: T.nilable(Integer)).returns(RunQueryOutput) }
          def query(offset:, limit:)
            rows = if (@repos_filterer.is_a?(EnterpriseReposFilterer) ||
              @repos_filterer.is_a?(OrgReposFilterer)) &&
              run_sliced_queries?
              # Run the query in parallel for each repos_slice4
              # Then re-order by open_alerts and take the first 10 repositories
              # Note that same repo can not get into multiple slices by definition, so rows are unique

              (0..3).map do |repos_slice4|
                sql = %{
                  SELECT
                    rev.repository_id,
                    rev.repository_name,
                    SUM(rev.open_alerts) AS open_alerts,
                    SUM(rev.critical) AS critical,
                    SUM(rev.high) AS high,
                    SUM(rev.medium) AS medium,
                    SUM(rev.low) AS low,
                    rev.owner_type
                  FROM (#{union_all_sql(slice_by: SliceBy.new(value_4_slices: repos_slice4, dimension: :by_repository))}) AS rev
                  GROUP BY rev.repository_id
                  ORDER BY open_alerts DESC, repository_id ASC
                  LIMIT 10
                }.squish

                ApplicationRecord::SecurityOverviewAnalytics.connection.select_all(sql, async: true)
              end
              # Async queries return above end up returning array of promise-like ActiveRecord::FutureResult objects
              # The objects have .then method which return completed promises with values
              .map { |promise| promise.then(&:rows) }
              .flat_map(&:value)
              .sort_by { |row| [-row[2], row[0]] }
              .first(10)
            else
              sql = %{
                SELECT
                  rev.repository_id,
                  rev.repository_name,
                  SUM(rev.open_alerts) AS open_alerts,
                  SUM(rev.critical) AS critical,
                  SUM(rev.high) AS high,
                  SUM(rev.medium) AS medium,
                  SUM(rev.low) AS low,
                  rev.owner_type
                FROM (#{union_all_sql}) AS rev
                GROUP BY rev.repository_id
                ORDER BY open_alerts DESC, repository_id ASC
                LIMIT 10
              }.squish

              ApplicationRecord::SecurityOverviewAnalytics.connection.select_rows(sql)
            end

            rows&.map do |row|
              {
                id: row[0],
                repository: row[1],
                total: row[2].round,
                critical: severity_count(row[3].round, "critical"),
                high: severity_count(row[4].round, "high"),
                medium: severity_count(row[5].round, "medium"),
                low: severity_count(row[6].round, "low"),
                owner_type: row[7]
              }
            end
          end

          sig { override.returns(String) }
          def union_all_fallback_sql
            %{
              SELECT
                NULL AS repository_id,
                NULL AS repository_name,
                NULL as owner_type,
                NULL AS open_alerts,
                NULL AS critical,
                NULL AS high,
                NULL AS medium,
                NULL AS low
              WHERE FALSE
            }.squish
          end

          sig { override.params(slice_by: T.nilable(SliceBy)).returns(ActiveRecord::Relation) }
          def code_scanning_rel(slice_by: nil)
            super
              .select(
                "COUNT(CASE WHEN alert_severity = 'critical' THEN 1 END) AS critical",
                "COUNT(CASE WHEN alert_severity = 'high' THEN 1 END) AS high",
                "COUNT(CASE WHEN alert_severity = 'medium' THEN 1 END) AS medium",
                "COUNT(CASE WHEN alert_severity = 'low' THEN 1 END) AS low"
              )
              .where("alert_severity IN ('critical', 'high', 'medium', 'low')")
          end

          sig { override.params(slice_by: T.nilable(SliceBy)).returns(ActiveRecord::Relation) }
          def dependabot_alerts_rel(slice_by: nil)
            super
              .select(
                "COUNT(CASE WHEN alert_severity = 'critical' THEN 1 END) AS critical",
                "COUNT(CASE WHEN alert_severity = 'high' THEN 1 END) AS high",
                "COUNT(CASE WHEN alert_severity = 'moderate' THEN 1 END) AS medium",
                "COUNT(CASE WHEN alert_severity = 'low' THEN 1 END) AS low"
              )
              .where("alert_severity IN ('critical', 'high', 'moderate', 'low')")
          end

          sig { override.params(slice_by: T.nilable(SliceBy)).returns(ActiveRecord::Relation) }
          def secret_scanning_rel(slice_by: nil)
            super
              .select(
                "COUNT(*) AS critical",
                "0 as high",
                "0 AS medium",
                "0 AS low"
              )
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
              .select(
                "repository_id",
                "#{::SecurityOverviewAnalytics::Repository.table_name}.name AS repository_name",
                "#{::SecurityOverviewAnalytics::Repository.table_name}.owner_type",
                "COUNT(*) AS open_alerts"
              )
              .joins(:repository_metadata)
              .where(alert_resolved: false, repository_id: repo_metadata_rel.select(:repository_id))
              .where("#{table_name}.next_revision_date_id > ?", end_date_id)
              .where("#{table_name}.date_id <= ?", end_date_id)
              .group("#{::SecurityOverviewAnalytics::Repository.table_name}.repository_id")
              .order("open_alerts DESC, repository_id ASC")
              .limit(10)
          end

          sig { params(severity: String).returns(T::Boolean) }
          def severity_selected?(severity)
            selected_severities = alerts_filterer.selected_severities
            selected_severities.include?(severity)
          end

          sig { params(count: Integer, severity: String).returns(T.nilable(Integer)) }
          def severity_count(count, severity)
            if count == 0 && !severity_selected?(severity)
              # If severity is not selected, the count should be irrelevant and we want to return N/A in the UI
              nil
            else
              count
            end
          end
        end
      end
    end
  end
end
