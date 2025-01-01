# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module AlertsFixedWithAutofixQueryBase
      extend T::Helpers

      AlertsFilterer = T.type_alias do
        T.any(
          SecurityOverviewAnalytics::Dashboards::CodeScanningMetrics::PullRequestAlertsFilterer,
          SecurityOverviewAnalytics::Dashboards::Overview::PreventionDataFilterer
        )
      end

      class Result < T::Struct
        const :accepted, Integer, default: 0
        const :suggested, Integer, default: 0
      end

      sig { overridable.params(repos_filterer: ReposFilterer, alerts_filterer: AlertsFilterer, start_date: ::Date, end_date: ::Date).returns(Result) }
      def query(repos_filterer:, alerts_filterer:, start_date:, end_date:)
        query = CodeScanningPullRequestAlert
          .where(repository_id: repos_filterer.cs_repo_metadata_rel.select(:repository_id))
          .where(date_id: Date.id_from_date(start_date)..Date.id_from_date(end_date))
          .then { |rel| alerts_filterer.apply(rel) }
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
