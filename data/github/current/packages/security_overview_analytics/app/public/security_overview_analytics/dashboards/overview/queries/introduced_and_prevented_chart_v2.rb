# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class IntroducedAndPreventedChartV2 < CodeScanningMetrics::Queries::AbstractQuery

          class DataPoint < T::Struct
            const :x, ::Date
            const :y, Integer
          end

          class Series < T::Struct
            const :label, String
            const :data, T::Array[DataPoint], default: []
          end

          class Result < T::Struct
            const :series, T::Array[Series], default: []
          end

          sig { returns(Result) }
          def perform
            date_ids = Overview::Queries::DateHelper.interval_date_ids(@start_date, @end_date)
            return Result.new if date_ids.empty?

            # If there are no repos matching the query, return empty (which shows a blankslate).
            # This is different than having no alerts, which is an expected case.
            return Result.new unless @repos_filterer.cs_repo_metadata_rel.exists?

            subquery_rel = CodeScanningPullRequestAlert
              .where(repository_id: @repos_filterer.cs_repo_metadata_rel.select(:repository_id))
              .where("`#{CodeScanningPullRequestAlert.table_name}`.`date_id` <= ?", Date.id_from_date(@end_date))
              .then { |rel| @alerts_filterer.apply(rel) }

            base_rel = CodeScanningPullRequestAlert
              .joins("JOIN (#{dates_sql(date_ids)}) AS `intervals`")
              .where(id: subquery_rel.select(:id))
              .where("`#{CodeScanningPullRequestAlert.table_name}`.`date_id` <= `intervals`.`date_id`")
              .group("`intervals`.`date_id`")

            result = Result.new.tap do |result|
              result.series << Series.new(label: "Introduced")
              result.series << Series.new(label: "Prevented")
            end

            base_rel.select(
              Arel.sql("`intervals`.`date_id` AS `date_id`"),
              Arel.sql(%{
                SUM(IF(
                  `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolved` = 0
                  OR (
                    `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolved` = 1
                    AND `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolution` IN (#{T.must(CodeScanningAlertRevision::RESOLUTIONS_MAPPING[:risk_accepted]).join(", ")})
                  )
                , 1, 0)) as `introduced`
              }.squish),
              Arel.sql(%{
                SUM(IF(
                  `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolved` = 1
                  AND (
                    `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolution` IS NULL
                    OR (
                      `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolution` NOT IN (#{T.must(CodeScanningAlertRevision::RESOLUTIONS_MAPPING[:false_positive]).join(", ")})
                      AND `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolution` NOT IN (#{T.must(CodeScanningAlertRevision::RESOLUTIONS_MAPPING[:risk_accepted]).join(", ")})
                    )
                  )
                , 1, 0)) as `prevented`
              }.squish),
            ).then do |rel|
              with_dates(rel, date_ids:) do |row|
                date = ::Date.parse(row["date"].to_s)
                result.series.each do |series|
                  column = T.let(series.label.parameterize.underscore, String)
                  series.data << DataPoint.new(x: date, y: row[column]&.to_i || 0)
                end
              end
            end

            result
          end

          sig do
            params(
              rel: ActiveRecord::Relation,
              date_ids: T::Array[Integer],
              block: T.proc.params(row: ActiveRecord::Result::IndexedRow).void
            ).void
          end
          def with_dates(rel, date_ids:, &block)
            sql = %{
              SELECT `dates`.`date_id` AS `date`, `data`.*
              FROM (#{dates_sql(date_ids)}) AS `dates`
              LEFT JOIN (#{rel.to_sql}) AS `data` ON `data`.`date_id` = `dates`.`date_id`
              ORDER BY `date`
            }.squish

            ApplicationRecord::SecurityOverviewAnalytics.connection.select_all(sql).each do |row|
              yield row
            end
          end

          sig { params(date_ids: T::Array[Integer]).returns(String) }
          def dates_sql(date_ids)
            date_ids.map do |date_id|
              %{
                SELECT #{date_id} AS `date_id`
              }.squish
            end.join(" UNION ALL ")
          end
        end
      end
    end
  end
end
