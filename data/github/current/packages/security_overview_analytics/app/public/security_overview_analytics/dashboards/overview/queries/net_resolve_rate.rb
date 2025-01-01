# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class NetResolveRate < Base
          RunQueryOutput = type_member { { fixed: Result } }

          class Result < T::Struct
            const :value, T.nilable(Integer)
            const :closed_count, T.nilable(Integer)
            const :open_count, T.nilable(Integer)
          end

          private

          sig { override.returns(RunQueryOutput) }
          def query
            alert_counts_sql = %{
              SELECT
                SUM(closed_count) AS closed_count,
                SUM(open_count) AS open_count
              FROM (#{union_all_sql}) AS alert_counts_inner
            }.squish

            if return_alert_count
              res = ApplicationRecord::SecurityOverviewAnalytics.connection.select_one(alert_counts_sql)&.to_h
              return Result.new(value: nil, closed_count: res&.values.first&.round || 0, open_count: res&.values.second&.round || 0)
            end

            res = ApplicationRecord::SecurityOverviewAnalytics.connection.select_value(%{
              SELECT COALESCE(closed_count, 0) / COALESCE(NULLIF(open_count, 0), 1) * 100 AS resolve_rate
              FROM (#{alert_counts_sql}) AS alert_counts
            }.squish)&.round || 0

            Result.new(value: res)
          end

          sig { override.returns(String) }
          def union_all_fallback_sql
            %{
              SELECT
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
            if alerts_filterer.alert_centric_filters_applied? && ::SecurityOverviewAnalytics::FeatureFlagHelper.use_alerts_filterer_class?(:severity, scope)
              # NRR applies calculation on both open and closed alerts. Since the base query may have already been
              # filtered to resolved alerts based on resolution, we need to unscope it here and include unresolved alerts.
              unscoped_rel = rel.unscope(where: :alert_resolution).unscope(where: :alert_resolved).where(alert_resolved: false)
              # If alert-centric filters apply, this union represents the resolved alerts with specific resolutions and severities,
              # plus the rest of open alerts with selected severities.
              rel = rel.or(unscoped_rel)
            end

            # Convert the start and end date IDs to MySQL's system timezone to match the created and resolved timezones.
            select_clause =
              %{
                SUM(IF(
                  #{table_name}.alert_resolved = 1
                  AND (#{table_name}.alert_resolved_at BETWEEN #{convert_utc_datetime_to_system_sql(start_date_id)} AND #{convert_utc_datetime_to_system_sql(day_after_end_date_id)}), 1, 0)
                ) AS closed_count,
                SUM(IF(
                  #{table_name}.alert_resolved = 0
                  AND (#{table_name}.alert_created_at BETWEEN #{convert_utc_datetime_to_system_sql(start_date_id)} AND #{convert_utc_datetime_to_system_sql(day_after_end_date_id)}), 1, 0)
                ) AS open_count
              }.squish

            rel
              .select(select_clause)
              .where(
                date_id: start_date_id..end_date_id,
                repository_id: repo_metadata_rel.select(:repository_id)
              )
              .where("#{table_name}.next_revision_date_id > ?", end_date_id)
          end
        end
      end
    end
  end
end
