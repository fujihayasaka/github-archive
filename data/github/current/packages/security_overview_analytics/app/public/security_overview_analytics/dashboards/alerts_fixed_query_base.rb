# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module AlertsFixedQueryBase
      extend T::Helpers

      AlertsFilterer = T.type_alias do
        T.any(
          SecurityOverviewAnalytics::Dashboards::CodeScanningMetrics::PullRequestAlertsFilterer,
          SecurityOverviewAnalytics::Dashboards::Overview::PreventionDataFilterer
        )
      end

      sig do
        overridable.params(
          repos_filterer: ReposFilterer,
          alerts_filterer: AlertsFilterer,
          start_date: ::Date,
          end_date: ::Date
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def query(repos_filterer:, alerts_filterer:, start_date:, end_date:)
        query = CodeScanningPullRequestAlert
          .where(repository_id: repos_filterer.cs_repo_metadata_rel.select(:repository_id))
          .where(date_id: Date.id_from_date(start_date)..Date.id_from_date(end_date))
          .then { |rel| alerts_filterer.apply(rel) }
          .select(
            Arel.sql(%{
              SUM(IF(
                `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolved` = 1
                AND `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolution` IS NULL
              , 1, 0)) AS `fixed`
            }.squish),
            Arel.sql("COUNT(*) as total")
          )

        ApplicationRecord::SecurityOverviewAnalytics.connection.select_one(query).to_h.symbolize_keys
      end
    end
  end
end
