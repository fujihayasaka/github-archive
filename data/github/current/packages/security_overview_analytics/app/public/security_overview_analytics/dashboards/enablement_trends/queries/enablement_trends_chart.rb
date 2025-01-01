# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module EnablementTrends
      module Queries
        class EnablementTrendsChart
          extend T::Helpers

          class Result < T::Struct

            const :date, ::Date
            const :total_repositories, Integer, default: 0
            const :dependabot_alerts_enabled, Integer, default: 0
            const :dependabot_security_updates_enabled, Integer, default: 0
            const :code_scanning_enabled, Integer, default: 0
            const :secret_scanning_enabled, Integer, default: 0
            const :secret_scanning_push_protection_enabled, Integer, default: 0
            const :dependabot_alerts_repositories_count, Integer, default: 0
            const :dependabot_security_updates_repositories_count, Integer, default: 0
            const :code_scanning_repositories_count, Integer, default: 0
            const :secret_scanning_repositories_count, Integer, default: 0
            const :secret_scanning_push_protection_repositories_count, Integer, default: 0

            sig { params(other: T.untyped).returns(T::Boolean) }
            def ==(other)
              return false unless other.is_a?(Result)
              self.serialize == other.serialize
            end
          end

          TScope = T.type_alias { T.any(::Business, ::Organization) }

          sig { returns(TScope) }
          attr_reader :scope

          sig { returns(::Date) }
          attr_reader :start_date, :end_date

          sig { returns(ReposFilterer) }
          attr_reader :repos_filterer

          sig do
            params(
              scope: TScope,
              start_date: ::Date,
              end_date: ::Date,
              repos_filterer: ReposFilterer,
            ).void
          end
          def initialize(scope:, start_date:, end_date:, repos_filterer:)
            @scope = scope
            @start_date = start_date
            @end_date = end_date
            @repos_filterer = repos_filterer
          end

          sig { returns(T::Array[Result]) }
          def perform
            GitHub.dogstats.distribution_time("security_overview_analytics.enablement_trends_chart.perform.dist") do
              query
            end
          end

          private

          ### Run sliced queries on non-GHES environments. On GHES, do not run sliced queries or parallelize, as there is no read replicas.
          sig { returns(T::Boolean) }
          def run_sliced_queries?
            !GitHub.enterprise?
          end

          sig { returns(T::Array[Result]) }
          def query
            date_ids = Dashboards::Overview::Queries::DateHelper.interval_date_ids(start_date, end_date)
            return [] if date_ids.empty?

            if run_sliced_queries?
              query_results = (0..3).map do |repos_slice4|
                sql = query_sql(repo_metadata_rel: repos_filterer.any_feature_repo_metadata_rel(repos_slice4:), date_ids:)
                ApplicationRecord::SecurityOverviewAnalytics.connection.select_all(sql, async: true)
              end
              # Async queries return above end up returning array of promise-like ActiveRecord::FutureResult objects
              # The objects have .then method which return completed promises with values
              .map { |promise| promise.then { |result| result } }
              .map(&:value)

              # Push values from each slice into combined set of values
              rows_by_date_id = {}
              query_results.each do |slice|
                slice.rows.each do |row|
                  if rows_by_date_id[row[0]].nil?
                    rows_by_date_id[row[0]] = row
                  else
                    row.each_with_index do |value, index|
                      next if index == 0 # skip the date_id
                      rows_by_date_id[row[0]][index] += value
                    end
                  end
                end
              end

              # convert date_id => row hash back into array of rows
              rows = rows_by_date_id.values

              query_results = ActiveRecord::Result.new(query_results.first.columns, rows, query_results.first.column_types)
            else
              sql = query_sql(repo_metadata_rel: repos_filterer.any_feature_repo_metadata_rel, date_ids:)
              query_results = ApplicationRecord::SecurityOverviewAnalytics.connection.select_all(sql)
            end

            # Hash results by date_id
            query_results = query_results.index_by { |row| row.fetch("date_id") }

            # We may not have revision data for one or more dates. We need to build the results using the desired dates,
            # including whatever data we DO have, and fill in zeroes for the rest.
            date_ids.map do |date_id|
              row = query_results.dig(date_id)

              Result.new(
                date:  ::Date.parse(date_id.to_s),
                total_repositories: row&.fetch("total_repositories")&.to_i || 0,
                dependabot_alerts_enabled: row&.fetch("dependabot_alerts_enabled")&.to_i || 0,
                dependabot_security_updates_enabled: row&.fetch("dependabot_security_updates_enabled")&.to_i || 0,
                code_scanning_enabled: row&.fetch("code_scanning_enabled")&.to_i || 0,
                secret_scanning_enabled: row&.fetch("secret_scanning_enabled")&.to_i || 0,
                secret_scanning_push_protection_enabled: row&.fetch("secret_scanning_push_protection_enabled")&.to_i || 0,
                dependabot_alerts_repositories_count: row&.fetch("dependabot_alerts_repositories_count")&.to_i || 0,
                dependabot_security_updates_repositories_count: row&.fetch("dependabot_security_updates_repositories_count")&.to_i || 0,
                code_scanning_repositories_count: row&.fetch("code_scanning_repositories_count")&.to_i || 0,
                secret_scanning_repositories_count: row&.fetch("secret_scanning_repositories_count")&.to_i || 0,
                secret_scanning_push_protection_repositories_count: row&.fetch("secret_scanning_push_protection_repositories_count")&.to_i || 0,
              )
            end
          end

          sig { params(repo_metadata_rel: ActiveRecord::Relation, date_ids: T::Array[Integer]).returns(String) }
          def query_sql(repo_metadata_rel:, date_ids:)

            # This is a workaround for mysql 5.7 not supporting VALUES clause
            dates_memory_table = date_ids.map { |date_id| "SELECT #{date_id} AS id" }.join(" UNION ALL ")

            sql = %{
              SELECT
                soa_dates.id AS date_id,
                COUNT(*) AS total_repositories,

                COALESCE(SUM(if(owner_type='user', 0, rev.dependabot_alerts_enabled)), 0) AS dependabot_alerts_enabled,
                COALESCE(SUM(if(owner_type='user', 0, rev.dependabot_security_updates_enabled)), 0) AS dependabot_security_updates_enabled,
                COALESCE(SUM(if(owner_type='user', 0, rev.code_scanning_enabled)), 0) AS code_scanning_enabled,
                COALESCE(SUM(rev.secret_scanning_enabled), 0) AS secret_scanning_enabled,
                COALESCE(SUM(rev.secret_scanning_push_protection_enabled), 0) AS secret_scanning_push_protection_enabled,

                COALESCE(SUM(if(owner_type='user', 0, 1)), 0) AS dependabot_alerts_repositories_count,
                COALESCE(SUM(if(owner_type='user', 0, 1)), 0) AS dependabot_security_updates_repositories_count,
                COALESCE(SUM(if(owner_type='user', 0, 1)), 0) AS code_scanning_repositories_count,
                COUNT(*) AS secret_scanning_repositories_count,
                COUNT(*) AS secret_scanning_push_protection_repositories_count

                FROM soa_feature_status_revisions rev
              JOIN (#{dates_memory_table}) soa_dates ON soa_dates.id >= rev.date_id AND soa_dates.id < rev.next_revision_date_id
              JOIN (#{repo_metadata_rel.select(:repository_id, :owner_type).to_sql}) rep
                ON rep.repository_id = rev.repository_id
              GROUP BY soa_dates.id
              ORDER BY soa_dates.id
            }.squish
          end
        end
      end
    end
  end
end
