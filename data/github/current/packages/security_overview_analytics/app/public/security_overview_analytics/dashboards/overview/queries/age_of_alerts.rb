# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AgeOfAlerts < Base
          class Result < T::Struct
            const :value, T.nilable(Float)
            const :alert_count, T.nilable(Integer)
          end

          RunQueryOutput = type_member { { fixed: Result } }

          private


          sig { params(union_all_sql_string: String).returns(String) }
          def generate_query(union_all_sql_string)
            %{
              SELECT AVG(age) AS avg_age, count(*) as alert_count
              FROM (#{union_all_sql_string}) as combined_ages
            }.squish
          end

          sig { override.returns(RunQueryOutput) }
          def query
            result = run_sliced_alert_revisions_query(accumulator: SingleValueAccumulator.new, results_reducer: avg_reducer(data_column: :avg_age, count_column: :alert_count)) do |union_all_sql_string|
              generate_query(union_all_sql_string)
            end
            Result.new(value: result.value.round.to_f, alert_count: result.alert_count)
          end

          sig { override.returns(String) }
          def union_all_fallback_sql
            "SELECT NULL AS age WHERE FALSE"
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
              # Convert the alert_created_at from system into UTC, and then take the date part of the result
              # The alert_created_at is stored in PST on dotcom, but our date comparisons/arithmetics uses UTC
              # Note that compared to other queries, here we have to convert the data (not parameter)
              # because the cutoff between previous and next day is calculated in UTC
              # This is slightly slower than converting the (static) parameters
              .select("DATEDIFF('#{end_date_str}', CAST(#{convert_datetime_to_utc_sql("#{table_name}.alert_created_at")} AS DATE)) AS age")
              .where(alert_resolved: false, repository_id: repo_metadata_rel.select(:repository_id))
              .where("#{table_name}.next_revision_date_id > ?", end_date_id)
              .where("#{table_name}.date_id <= ?", end_date_id)
          end

          sig { returns(String) }
          memoize def end_date_str
            end_date.strftime("%Y-%m-%d")
          end
        end
      end
    end
  end
end
