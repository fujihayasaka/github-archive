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

          sig { override.returns(RunQueryOutput) }
          def query
            if return_alert_count
              res = ApplicationRecord::SecurityOverviewAnalytics.connection.select_one(%{
                SELECT AVG(age) AS avg_age, count(*) as alert_count
                FROM (#{union_all_sql}) as combined_ages
              }.squish)&.to_h

              Result.new(value: res&.values.first.to_f || 0.to_f, alert_count: res&.values.second.round || 0)
            else
              sql = %{
                SELECT AVG(age)
                FROM (#{union_all_sql}) AS combined_ages
              }.squish

              Result.new(value: ApplicationRecord::SecurityOverviewAnalytics.connection.select_value(sql)&.round.to_f || 0.to_f)
            end


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
