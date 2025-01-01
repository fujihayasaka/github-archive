# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class NetResolveRate < Base
          RunQueryOutput = type_member { { fixed: Result } }

          class Result < T::Struct
            const :value, T.nilable(Integer)
            const :closed_count, T.nilable(Integer)
            const :open_count, T.nilable(Integer)
          end

          private

          sig { params(union_all_sql_string: String).returns(String) }
          def generate_query(union_all_sql_string)
            %{
              SELECT
                SUM(closed_count) AS closed_count,
                SUM(open_count) AS open_count
              FROM (#{union_all_sql_string}) AS alert_counts_inner
            }.squish
          end

          class NRRAccumulator < T::Struct
            prop :closed_count, Integer, default: 0
            prop :open_count, Integer, default: 0

            sig { params(closed_count: Integer, open_count: Integer).void }
            def initialize(closed_count: 0, open_count: 0)
              super
            end
          end

          sig { override.params(offset: T.nilable(Integer), limit: T.nilable(Integer)).returns(RunQueryOutput) }
          def query(offset:, limit:)
            results_reducer = ->(accumulator, slice_result) {
              return accumulator if slice_result["closed_count"] == 0 && slice_result["open_count"] == 0

              closed_count = (slice_result["closed_count"] || 0).round
              open_count = (slice_result["open_count"] || 0).round

              accumulator.closed_count += closed_count
              accumulator.open_count += open_count

              accumulator
            }

            result = run_sliced_alert_revisions_query(accumulator: NRRAccumulator.new, results_reducer:) do |union_all_sql_string|
              generate_query(union_all_sql_string)
            end

            Result.new(value: nil, closed_count: result.closed_count, open_count: result.open_count)
          end

          sig { override.returns(String) }
          def union_all_fallback_sql
            %{
              SELECT
                NULL AS closed_count,
                NULL AS open_count
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
            # Convert the start and end date IDs to MySQL's system timezone to match the created and resolved timezones.
            select_clause =
              %{
                SUM(IF(
                  #{table_name}.alert_resolved = 1
                  AND (#{table_name}.alert_resolved_at BETWEEN #{convert_utc_datetime_to_system_sql(start_date_id)} AND #{convert_utc_datetime_to_system_sql(day_after_end_date_id)}), 1, 0)
                ) AS closed_count,
                SUM(IF(
                  #{table_name}.alert_resolved = 0
                  AND (#{table_name}.alert_created_at BETWEEN #{convert_utc_datetime_to_system_sql(start_date_id)} AND #{convert_utc_datetime_to_system_sql(day_after_end_date_id)}), 1, 0)
                ) AS open_count
              }.squish

            rel
              .select(select_clause)
              .where(
                date_id: start_date_id..end_date_id,
                repository_id: repo_metadata_rel.select(:repository_id)
              )
              .where("#{table_name}.next_revision_date_id > ?", end_date_id)
          end
        end
      end
    end
  end
end
