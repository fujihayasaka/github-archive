# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      module Queries
        class RemediationRatesQuery < AbstractQuery
          extend T::Helpers

          class Result < T::Struct
            const :percentFixedWithAutofixSuggested, Integer
            const :percentFixedWithNoAutofixSuggested, Integer
          end

          sig { returns(Result) }
          def perform
            query = CodeScanningPullRequestAlert
              .where(repository_id: @repos_filterer.cs_repo_metadata_rel.select(:repository_id))
              .where(date_id: Date.id_from_date(@start_date)..Date.id_from_date(@end_date))
              .then { |rel| @alerts_filterer.apply(rel) }
              .select(
                Arel.sql(%{
                  SUM(IF(
                    `#{CodeScanningPullRequestAlert.table_name}`.`has_autofix` = 1
                  , 1, 0)) as has_autofix
                }.squish),
                Arel.sql(%{
                  SUM(IF(
                    `#{CodeScanningPullRequestAlert.table_name}`.`has_autofix` = 1
                    AND `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolved` = 1
                    AND `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolution` IS NULL
                  , 1, 0)) as has_autofix_and_fixed
                }.squish),
                Arel.sql(%{
                  SUM(IF(
                    `#{CodeScanningPullRequestAlert.table_name}`.`has_autofix` != 1
                  , 1, 0)) as no_autofix
                }.squish),
                Arel.sql(%{
                  SUM(IF(
                    `#{CodeScanningPullRequestAlert.table_name}`.`has_autofix` != 1
                    AND `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolved` = 1
                    AND `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolution` IS NULL
                  , 1, 0)) as no_autofix_and_fixed
                }.squish),
              )

            result = ApplicationRecord::SecurityOverviewAnalytics.connection.select_one(query).to_h.symbolize_keys

            Result.new(
                percentFixedWithAutofixSuggested: percentage(
                  result[:has_autofix_and_fixed]&.to_i || 0,
                  result[:has_autofix]&.to_i || 0,
                ).to_i,
                percentFixedWithNoAutofixSuggested: percentage(
                  result[:no_autofix_and_fixed]&.to_i || 0,
                  result[:no_autofix]&.to_i || 0,
                ).to_i,
            )
          end
        end
      end
    end
  end
end
