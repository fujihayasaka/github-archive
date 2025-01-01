# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module UnifiedAlerts
    class CountsDataQuery < DataQuery
      extend T::Sig

      class Result < T::Struct
        const :open, Integer
        const :closed, Integer
      end

      sig { returns(Result) }
      def run
        union_all_query_parts = T.let([], T::Array[String])
        security_features.each do |feature|
          feature_base_rel = security_feature_base_rel(feature)
          next if feature_base_rel.nil?

          feature_module = T.must(SECURITY_FEATURE_MODEL_MAPPINGS[feature])
          union_all_query_parts << "(#{
            feature_base_rel
              .unscope(where: :alert_resolved)
              .select(
                Arel.sql("SUM(IF(`#{feature_module.table_name}`.`alert_resolved` = 0, 1, 0)) AS open_count"),
                Arel.sql("SUM(IF(`#{feature_module.table_name}`.`alert_resolved` = 1, 1, 0)) AS closed_count")
              )
              .to_sql
          })"
        end
        return Result.new(open: 0, closed: 0) if union_all_query_parts.empty?

        unified_alerts = union_all_query_parts.join(" UNION ALL ")
        full_sql = %{
          SELECT SUM(open_count) AS open_count, SUM(closed_count) AS closed_count
          FROM (#{unified_alerts}) AS unified
        }.squish

        rows = T.cast(ApplicationRecord::SecurityOverviewAnalytics.connection.select_rows(full_sql), T::Array[T::Array[T.untyped]])
        return Result.new(open: 0, closed: 0) if rows.empty?

        open_count, close_count = T.must(rows[0])
        Result.new(open: open_count.to_i || 0, closed: close_count.to_i || 0)
      end
    end
  end
end
