# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AlertActivityChart < Base
          RunQueryOutput = type_member { { fixed: T::Array[T::Hash[Symbol, T.any(String, Integer)]] } }

          private

          sig { params(union_all_sql_string: String).returns(String) }
          def generate_query(union_all_sql_string)
            %{
              SELECT
                intervals.start_date_id,
                intervals.end_date_id,
                SUM(closed_count) AS closed_count,
                SUM(open_count) AS open_count
              FROM
                (#{intervals_union_sql}) AS intervals
                  LEFT JOIN (#{union_all_sql_string}) rev
                    ON rev.end_date_id = intervals.end_date_id
              GROUP BY intervals.end_date_id, intervals.start_date_id;
            }.squish
          end

          sig { override.params(offset: T.nilable(Integer), limit: T.nilable(Integer)).returns(RunQueryOutput) }
          def query(offset:, limit:)
            run_sliced_alert_revisions_query(accumulator: {},
              results_reducer: ->(accumulator, slice_result) {
                date = ::Date.parse(slice_result.fetch("start_date_id").to_s)
                end_date = ::Date.parse(slice_result.fetch("end_date_id").to_s)

                if accumulator[date]
                  accumulator[date][:closed] += slice_result.fetch("closed_count")&.round || 0
                  accumulator[date][:opened] += slice_result.fetch("open_count")&.round || 0
                else
                  accumulator[date] = {
                    date: date,
                    end_date: end_date,
                    closed: slice_result.fetch("closed_count")&.round || 0,
                    opened: slice_result.fetch("open_count")&.round || 0,
                  }
                end

                accumulator
              }
            ) do |union_all_sql_string|
              generate_query(union_all_sql_string)
            end.values
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


          # Overrides base union_all_sql, but still supports slicing
          # Does not slice repos, rules or advisories, just alert revisions
          sig { override.params(slice_by: T.nilable(SliceBy)).returns(String) }
          def union_all_sql(slice_by: nil)
            dates_subquery = intervals_union_sql
            query_parts = []
            alert_revisions_slice4 = slice_by&.dimension == :by_alert_revision ? slice_by&.value_4_slices : nil

            query_parts << code_scanning_sql(dates_subquery:, alert_revisions_slice4:) if include_code_scanning?
            query_parts << dependabot_alerts_sql(dates_subquery:, alert_revisions_slice4:) if include_dependabot_alerts?
            query_parts << secret_scanning_sql(dates_subquery:, alert_revisions_slice4:) if include_secret_scanning?

            return query_parts.join(" UNION ALL ") if query_parts.any?

            union_all_fallback_sql
          end

          sig { params(dates_subquery: String, alert_revisions_slice4: T.nilable(Integer)).returns(String) }
          def code_scanning_sql(dates_subquery:, alert_revisions_slice4: nil)
            rel = code_scanning_rel.then do |rel|
              # Alert activity chart queries in range revisions and outputs primary key of the table.
              # In rare cases, MySQL uses a table scan since there are only range query clauses if no alert filters.
              if alert_revisions_slice4
                rel.use_index("index_soa_slice4_cs_alert_revs_on_dashboard_dates_coverage")
              else
                rel.use_index("index_soa_code_scanning_alert_revs_on_dashboard_dates_coverage")
              end
            end
            union_sql(rel, dates_subquery, CodeScanningAlertRevision, alert_revisions_slice4)
          end

          sig { params(dates_subquery: String, alert_revisions_slice4: T.nilable(Integer)).returns(String) }
          def secret_scanning_sql(dates_subquery:, alert_revisions_slice4: nil)
            rel = secret_scanning_rel.then do |rel|
              # Alert activity chart queries in range revisions and outputs primary key of the table.
              # In rare cases, MySQL uses a table scan since there are only range query clauses if no alert filters.
              if alert_revisions_slice4
                rel.use_index("index_soa_slice4_ss_alert_revs_on_dashboard_dates_coverage")
              else
                rel.use_index("index_soa_secret_scanning_alert_revs_on_dashboard_dates_coverage")
              end
            end
            union_sql(rel, dates_subquery, SecretScanningAlertRevision, alert_revisions_slice4)
          end

          sig { params(dates_subquery: String, alert_revisions_slice4: T.nilable(Integer)).returns(String) }
          def dependabot_alerts_sql(dates_subquery:, alert_revisions_slice4: nil)
            rel = dependabot_alerts_rel.then do |rel|
              # Alert activity chart queries in range revisions and outputs primary key of the table.
              # In rare cases, MySQL uses a table scan since there are only range query clauses if no alert filters.
              if alert_revisions_slice4
                rel.use_index("index_soa_slice4_da_revs_on_dashboard_dates_coverage")
              else
                rel.use_index("index_soa_dependabot_alert_revs_on_dashboard_dates_coverage")
              end
            end
            union_sql(rel, dates_subquery, DependabotAlertRevision, alert_revisions_slice4)
          end

          sig do params(
            rel: ActiveRecord::Relation,
            dates_subquery: String,
            model: T.any(T.class_of(CodeScanningAlertRevision), T.class_of(DependabotAlertRevision), T.class_of(SecretScanningAlertRevision)),
            alert_revisions_slice4: T.nilable(Integer)
            ).returns(String)
          end
          def union_sql(rel, dates_subquery, model, alert_revisions_slice4)
            table_name = model.table_name

            if alert_revisions_slice4
              rel = rel.where(slice4: alert_revisions_slice4)
            end

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
