# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class ReopenedAlerts < Base
          RunQueryOutput = type_member { { fixed: Integer } }

          private

          sig { params(union_all_sql_string: String).returns(String) }
          def generate_query(union_all_sql_string)
            %{
              SELECT SUM(counts) AS total_count
              FROM (#{union_all_sql_string}) AS combined_counts
            }.squish
          end

          sig { override.returns(RunQueryOutput) }
          def query
            # This code path works when using server-side slicing
            result = run_sliced_alert_revisions_query(accumulator: SingleValueAccumulator.new, results_reducer: count_reducer(count_column: :total_count)) do |union_all_sql_string|
              generate_query(union_all_sql_string)
            end

            result.alert_count
          end

          sig { override.returns(String) }
          def union_all_fallback_sql
            "SELECT NULL AS counts WHERE FALSE"
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
              .select("COUNT(*) AS counts")
              .where(alert_resolved: false, repository_id: repo_metadata_rel.select(:repository_id))
              .where("#{table_name}.next_revision_date_id > ?", end_date_id)
              .where("#{table_name}.alert_reopened_at BETWEEN #{convert_utc_datetime_to_system_sql(start_date_id)} AND #{convert_utc_datetime_to_system_sql(day_after_end_date_id)}")
          end
        end
      end
    end
  end
end
