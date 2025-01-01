# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      module Queries
        class AlertsFoundQuery < AbstractQuery
          extend T::Helpers

          class Result < T::Struct
            const :count, Integer
          end

          sig { returns(Result) }
          def perform
            # query 1: resolved/open in PRs
            query1 = CodeScanningPullRequestAlert
              .where(repository_id: @repos_filterer.cs_repo_metadata_rel.select(:repository_id))
              .where(date_id: Date.id_from_date(@start_date)..Date.id_from_date(@end_date))
              .then { |rel| @alerts_filterer.apply(rel) }
              .select(
                Arel.sql("SUM(IF(`#{CodeScanningPullRequestAlert.table_name}`.`alert_resolved` = 1, 1, 0)) as prevented_in_prs"),
                Arel.sql("SUM(IF(`#{CodeScanningPullRequestAlert.table_name}`.`alert_resolved` = 0, 1, 0)) as unresolved_in_prs"),
              )

            result1 = ApplicationRecord::SecurityOverviewAnalytics.connection.select_one(query1).to_h.symbolize_keys
            prevented_in_prs = result1[:prevented_in_prs]&.to_i || 0
            unresolved_in_prs = result1[:unresolved_in_prs]&.to_i || 0

            Result.new(
              count: prevented_in_prs + unresolved_in_prs,
            )
          end

          private

          sig { params(value: ::Date).returns(String) }
          def convert_datetime_to_utc_sql(value)
            "convert_tz(#{Date.id_from_date(value)},'system','+00:00')"
          end
        end
      end
    end
  end
end
