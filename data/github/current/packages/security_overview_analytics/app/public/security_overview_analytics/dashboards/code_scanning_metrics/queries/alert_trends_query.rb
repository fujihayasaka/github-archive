# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      module Queries
        class AlertTrendsQuery < AbstractQuery
          extend T::Helpers

          Resolution = ::Turboscan::Proto::ResultResolution

          class GroupOption < T::Enum
            enums do
              Status = new
              Severity = new
            end
          end

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

          sig do
            params(
              scope: T.any(::Business, ::Organization),
              user: ::User,
              repos_filterer: ReposFilterer,
              alerts_filterer: PullRequestAlertsFilterer,
              start_date: ::Date,
              end_date: ::Date,
            ).void
          end
          def initialize(scope:, user:, repos_filterer:, alerts_filterer:, start_date:, end_date:)
            super
            @scope = scope
            @user = user
          end

          sig { params(group_by: GroupOption).returns(Result) }
          def perform(group_by:)
            date_ids = Overview::Queries::DateHelper.interval_date_ids(@start_date, @end_date)
            return Result.new if date_ids.empty?

            subquery_rel = CodeScanningPullRequestAlert
              .where(repository_id: @repos_filterer.cs_repo_metadata_rel.select(:repository_id))
              .where(date_id: Date.id_from_date(@start_date)..Date.id_from_date(@end_date))
              .then { |rel| @alerts_filterer.apply(rel) }

            base_rel = CodeScanningPullRequestAlert
              .joins("JOIN (#{intervals_sql(date_ids)}) AS `intervals`")
              .where(id: subquery_rel.select(:id))
              .where("`#{CodeScanningPullRequestAlert.table_name}`.`date_id` >= `intervals`.`start_date_id`")
              .where("`#{CodeScanningPullRequestAlert.table_name}`.`date_id` <= `intervals`.`end_date_id`")
              .group("`intervals`.`end_date_id`")

            case group_by
            when GroupOption::Status
              to_result_by_status(base_rel, date_ids:)
            when GroupOption::Severity
              to_result_by_severity(base_rel, date_ids:)
            else
              T.absurd(group_by)
            end
          end

          private

          sig { params(base_rel: ActiveRecord::Relation, date_ids: T::Array[Integer]).returns(Result) }
          def to_result_by_status(base_rel, date_ids:)
            result = Result.new.tap do |result|
              result.series << Series.new(label: "Unresolved and merged")
              result.series << Series.new(label: "Fixed with autofix")
              result.series << Series.new(label: "Fixed without autofix")
              result.series << Series.new(label: "Dismissed")
            end

            base_rel.select(
              Arel.sql("`intervals`.`end_date_id` AS `date_id`"),
              Arel.sql(%{
                SUM(IF(
                  `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolved` = 0
                , 1, 0)) as `unresolved_and_merged`
              }.squish),
              Arel.sql(%{
                SUM(IF(
                  `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolved` = 1
                  AND `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolution` IS NULL
                  AND `#{CodeScanningPullRequestAlert.table_name}`.`autofix_accepted` = 1
                , 1, 0)) AS `fixed_with_autofix`
              }.squish),
              Arel.sql(%{
                SUM(IF(
                  `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolved` = 1
                  AND `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolution` IS NULL
                  AND `#{CodeScanningPullRequestAlert.table_name}`.`autofix_accepted` = 0
                , 1, 0)) AS `fixed_without_autofix`
              }.squish),
              Arel.sql(%{
                SUM(IF(
                  `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolved` = 1
                  AND `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolution` IS NOT NULL
                , 1, 0)) AS `dismissed`
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

          sig { params(base_rel: ActiveRecord::Relation, date_ids: T::Array[Integer]).returns(Result) }
          def to_result_by_severity(base_rel, date_ids:)
            result = Result.new.tap do |result|
              result.series << Series.new(label: "Critical")
              result.series << Series.new(label: "High")
              result.series << Series.new(label: "Medium")
              result.series << Series.new(label: "Low")
            end

            base_rel.select(
              Arel.sql("`intervals`.`end_date_id` AS `date_id`"),
              Arel.sql(%{
                SUM(IF(
                  `#{CodeScanningPullRequestAlert.table_name}`.`alert_severity` = 'CRITICAL'
                , 1, 0)) as `critical`
              }.squish),
              Arel.sql(%{
                SUM(IF(
                  `#{CodeScanningPullRequestAlert.table_name}`.`alert_severity` = 'HIGH'
                , 1, 0)) as `high`
              }.squish),
              Arel.sql(%{
                SUM(IF(
                  `#{CodeScanningPullRequestAlert.table_name}`.`alert_severity` = 'MEDIUM'
                , 1, 0)) as `medium`
              }.squish),
              Arel.sql(%{
                SUM(IF(
                  `#{CodeScanningPullRequestAlert.table_name}`.`alert_severity` = 'LOW'
                , 1, 0)) as `low`
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
          def intervals_sql(date_ids)
            date_ids.each_with_index.map do |date_id, i|
              interval_end_date_id = date_id
              interval_start_date_id = if i == 0
                date_id
              else
                interval_start_date_id = T.must(date_ids[i - 1])
                interval_start_date_id += 1 if interval_start_date_id < interval_end_date_id
              end

              %{
                SELECT #{interval_start_date_id} AS `start_date_id`, #{interval_end_date_id} AS `end_date_id`
              }.squish
            end.join(" UNION ALL ")
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
