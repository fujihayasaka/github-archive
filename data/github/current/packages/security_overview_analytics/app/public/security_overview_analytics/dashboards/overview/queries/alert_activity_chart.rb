# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AlertActivityChart < Base
          RunQueryOutput = type_member { { fixed: T::Array[T::Hash[Symbol, T.any(String, Integer)]] } }

          private

          sig { override.returns(RunQueryOutput) }
          def query
            sql = %{
              SELECT
                intervals.start_date_id,
                intervals.end_date_id,
                SUM(closed_count) AS closed_count,
                SUM(open_count) AS open_count
              FROM
                (#{intervals_union_sql}) AS intervals
                  LEFT JOIN (#{union_all_sql_with_dates(intervals_union_sql)}) rev
                    ON rev.end_date_id = intervals.end_date_id
              GROUP BY intervals.end_date_id, intervals.start_date_id;
            }.squish

            ApplicationRecord::SecurityOverviewAnalytics.connection.select_rows(sql).map do |row|
              {
                date: ::Date.parse(row[0].to_s),
                end_date: ::Date.parse(row[1].to_s),
                closed: row[2].to_i,
                opened: row[3].to_i,
              }
            end
          end

          sig { override.returns(String) }
          def union_all_fallback_sql
            %{
              SELECT
                NULL AS start_date_id,
                NULL AS end_date_id,
                NULL AS closed_count,
                NULL AS open_count
              WHERE FALSE
            }.squish
          end

          sig do
            override.params(
              rel: ActiveRecord::Relation,
              repo_metadata_rel: ActiveRecord::Relation,
              table_name: String
            ).returns(ActiveRecord::Relation)
          end
          def common_clauses_rel(rel, repo_metadata_rel, table_name)
            start_date_id = ::SecurityOverviewAnalytics::Date.id_from_date(start_date)
            end_date_id = ::SecurityOverviewAnalytics::Date.id_from_date(end_date)

            rel
              .where("#{table_name}.date_id >= #{start_date_id}")
              .where("#{table_name}.date_id <= #{end_date_id}")
              .where(repository_id: repo_metadata_rel.select(:repository_id))
          end

          sig { params(dates_subquery: String).returns(String) }
          def union_all_sql_with_dates(dates_subquery)
            query_parts = []
            query_parts << code_scanning_sql(dates_subquery) if include_code_scanning?
            query_parts << dependabot_alerts_sql(dates_subquery) if include_dependabot_alerts?
            query_parts << secret_scanning_sql(dates_subquery) if include_secret_scanning?

            return query_parts.join(" UNION ALL ") if query_parts.any?

            union_all_fallback_sql
          end

          sig { params(dates_subquery: String).returns(String) }
          def code_scanning_sql(dates_subquery)
            union_sql(code_scanning_rel, dates_subquery, CodeScanningAlertRevision)
          end

          sig { params(dates_subquery: String).returns(String) }
          def secret_scanning_sql(dates_subquery)
            union_sql(secret_scanning_rel, dates_subquery, SecretScanningAlertRevision)
          end

          sig { params(dates_subquery: String).returns(String) }
          def dependabot_alerts_sql(dates_subquery)
            union_sql(dependabot_alerts_rel, dates_subquery, DependabotAlertRevision)
          end

          sig { params(rel: ActiveRecord::Relation, dates_subquery: String, model: T.any(T.class_of(CodeScanningAlertRevision), T.class_of(DependabotAlertRevision), T.class_of(SecretScanningAlertRevision))).returns(String) }
          def union_sql(rel, dates_subquery, model)
            table_name = model.table_name

            model \
              .select(
                "SUM(IF(`#{table_name}`.`alert_resolved` = 1 AND (#{table_name}.alert_resolved_at between intervals.start_date and intervals.end_date_eod), 1, 0)) AS closed_count",
                "SUM(IF(`#{table_name}`.`alert_resolved` = 0 AND (#{table_name}.alert_created_at between intervals.start_date and intervals.end_date_eod), 1, 0)) AS open_count",
                "intervals.end_date_id",
              )
              .joins("JOIN (#{dates_subquery}) intervals")
              .where(id: rel)
              .where("#{table_name}.date_id >= intervals.start_date_id")
              .where("#{table_name}.date_id <= intervals.end_date_id")
              .where("#{table_name}.next_revision_date_id > intervals.end_date_id")
              .group("intervals.end_date_id")
              .to_sql
          end

          sig { returns(String) }
          memoize def intervals_union_sql
            # Increase the overall range by a day so that the entire end day is included in the interval ranges used in the SQL.
            date_ids = DateHelper.interval_date_ids(start_date, end_date.next_day(1))

            T.must(date_ids[0..-2])
              .each_with_index
              .map do |date_id, i|
                next_date = ::Date.parse(date_ids[i + 1].to_s)
                next_date_id = ::SecurityOverviewAnalytics::Date.id_from_date(next_date)

                interval_end_date = next_date - 1
                interval_end_date_id = ::SecurityOverviewAnalytics::Date.id_from_date(interval_end_date)

                # Convert the (start) date_id and next_date from UTC into mysql system timezone
                # This will move for example 2021-11-01 to 2021-10-31 17:00 PST (on dotcom, mysql runs in PST)
                # Without this fix, the alerts created between 17:00 PST and midnight fall into 31st
                # Note that date_id for when revision happened is correctly calculated in UTC, so we don't need to convert it
                # for finding revisions on the day (i.e. the calendar in UI is matching the date_id values)
                %{
                  SELECT
                  #{date_id} AS start_date_id,
                  #{interval_end_date_id} AS end_date_id,
                  #{convert_utc_datetime_to_system_sql(date_id)} AS start_date,
                  #{convert_utc_datetime_to_system_sql(next_date_id)} AS end_date_eod
                }.squish
              end
              .join(" UNION ALL ")
          end
        end
      end
    end
  end
end
