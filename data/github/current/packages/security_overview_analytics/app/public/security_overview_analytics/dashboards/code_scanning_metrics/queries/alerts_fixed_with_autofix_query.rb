# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      module Queries
        class AlertsFixedWithAutofixQuery < AbstractQuery
          extend T::Helpers
          extend T::Sig

          class Result < T::Struct
            const :accepted, Integer
            const :suggested, Integer
          end

          sig { returns(Result) }
          def perform
            query = CodeScanningPullRequestAlert
              .where(repository_id: @repos_filterer.cs_repo_metadata_rel.select(:repository_id))
              .where(date_id: Date.id_from_date(@start_date)..Date.id_from_date(@end_date))
              .then { |rel| @alerts_filterer.apply(rel) }
              .where(has_autofix: true)
              .select(
                Arel.sql(%{
                  SUM(IF(
                    `#{CodeScanningPullRequestAlert.table_name}`.`autofix_accepted` = 1
                    AND `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolved` = 1
                    AND `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolution` IS NULL
                  , 1, 0)) as accepted
                }.squish),
                Arel.sql("COUNT(*) as suggested"),
              )

            result = ApplicationRecord::SecurityOverviewAnalytics.connection.select_one(query).to_h.symbolize_keys

            Result.new(
              accepted: result[:accepted]&.to_i || 0,
              suggested: result[:suggested]&.to_i || 0,
            )
          end
        end
      end
    end
  end
end
