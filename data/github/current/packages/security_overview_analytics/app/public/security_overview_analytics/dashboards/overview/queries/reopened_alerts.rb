# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class ReopenedAlerts < Base
          RunQueryOutput = type_member { { fixed: Integer } }

          private

          sig { override.returns(RunQueryOutput) }
          def query
            sql = %{
              SELECT SUM(counts) AS total_count
              FROM (#{union_all_sql}) AS combined_counts
            }.squish

            ApplicationRecord::SecurityOverviewAnalytics.connection.select_value(sql).to_i
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
