# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      module Queries
        class RemediationTimeQuery < AbstractQuery
          extend T::Helpers

          class Result < T::Struct
            const :remediationTimeInHoursWithAutofixSuggested, Float
            const :remediationTimeInHoursWithNoAutofixSuggested, Float
          end

          sig { returns(Result) }
          def perform
            query = CodeScanningPullRequestAlert
              .where(repository_id: @repos_filterer.cs_repo_metadata_rel.select(:repository_id))
              .where(date_id: Date.id_from_date(@start_date)..Date.id_from_date(@end_date))
              .then { |rel| @alerts_filterer.apply(rel) }
              .where(alert_resolved: true, alert_resolution: nil)
              .group(:has_autofix)
              .average(Arel.sql("TIMESTAMPDIFF(HOUR, alert_created_at, alert_resolved_at)"))

            Result.new(
              remediationTimeInHoursWithNoAutofixSuggested: query[false]&.to_f || 0.0,
              remediationTimeInHoursWithAutofixSuggested:  query[true]&.to_f || 0.0,
            )
          end
        end
      end
    end
  end
end
