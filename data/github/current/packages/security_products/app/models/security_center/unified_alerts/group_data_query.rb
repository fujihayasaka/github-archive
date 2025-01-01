# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module UnifiedAlerts
    class GroupDataQuery < DataQuery
      extend T::Sig

      PAGE_SIZE = 25

      AlertGroupData = T.type_alias { T::Hash[Symbol, T.untyped] }

      class Result < T::Struct
        const :alert_groups, T::Array[AlertGroupData]
        const :previous, T.nilable(String)
        const :next, T.nilable(String)
      end

      sig { params(group_key: String, cursor: String, page_size: Integer).returns(Result) }
      def run(group_key, cursor: "0", page_size: PAGE_SIZE)
        offset = T.let(Integer(cursor, exception: false), T.nilable(Integer))
        raise ArgumentError, "Unexpected `cursor` input." if offset.nil? || offset < 0

        return Result.new(alert_groups: []) if page_size <= 0

        group = Groups::GroupLookup.from(group_key, scope:, user:)
        return Result.new(alert_groups: []) if group.nil?

        limit = page_size + 1 # To know if it is the last page
        subquery_limit = offset + limit

        union_all_query_parts = T.let([], T::Array[String])
        security_features.each do |feature|
          feature_base_rel = security_feature_base_rel(feature)
          next if feature_base_rel.nil?

          feature_module = T.must(SECURITY_FEATURE_MODEL_MAPPINGS[feature])
          is_secret_scanning = feature == SecurityFeatures::SECRET_SCANNING
          union_all_query_parts << "(#{
            feature_base_rel
              .select(
                Arel.sql("#{is_secret_scanning ? "SUM(IF(`#{feature_module.table_name}`.`alert_number` IS NOT NULL, 1, 0))" : "SUM(IF(`#{feature_module.table_name}`.`alert_severity` = 'CRITICAL', 1, 0))"} AS `count_critical`"),
                Arel.sql("#{is_secret_scanning ? "0" : "SUM(IF(`#{feature_module.table_name}`.`alert_severity` = 'HIGH', 1, 0))"} AS `count_high`"),
                Arel.sql("#{is_secret_scanning ? "0" : "SUM(IF(`#{feature_module.table_name}`.`alert_severity` IN ('MODERATE', 'MEDIUM'), 1, 0))"} AS `count_medium`"),
                Arel.sql("#{is_secret_scanning ? "0" : "SUM(IF(`#{feature_module.table_name}`.`alert_severity` = 'LOW', 1, 0))"} AS `count_low`"),
                Arel.sql("SUM(IF(`#{feature_module.table_name}`.`alert_number` IS NOT NULL, 1, 0)) AS `total`")
              )
              .then { |rel| group.apply(rel, feature) }
              .group(:group)
              .order(count_critical: :desc, count_high: :desc, count_medium: :desc, count_low: :desc, total: :desc, group: :asc)
              .limit(subquery_limit)
              .to_sql
          })"
        end
        return Result.new(alert_groups: []) if page_size <= 0

        unified_alerts = union_all_query_parts.join(" UNION ALL ")
        full_sql = %{
          SELECT `group`,
            SUM(`count_critical`) AS `count_critical`,
            SUM(`count_high`) AS `count_high`,
            SUM(`count_medium`) AS `count_medium`,
            SUM(`count_low`) AS `count_low`,
            SUM(`total`) AS `total`
          FROM (#{unified_alerts}) AS `unified`
          GROUP BY `group`
          ORDER BY `count_critical` DESC,
            `count_high` DESC,
            `count_medium` DESC,
            `count_low` DESC,
            `total` DESC,
            `group` ASC
          LIMIT #{limit} OFFSET #{offset}
        }.squish

        alert_groups = T.let([], T::Array[AlertGroupData])
        is_last_page = T.let(true, T::Boolean)
        ApplicationRecord::SecurityOverviewAnalytics.connection.select_all(full_sql).each_with_index do |row, index|
          if index >= page_size
            is_last_page = false
            next # Skip alert after page_size limit
          end

          alert_groups << {
            key: "#{group_key}:#{row.fetch("group")}",
            name: row.fetch("group"),
            count_critical: row.fetch("count_critical").to_i,
            count_high: row.fetch("count_high").to_i,
            count_medium: row.fetch("count_medium").to_i,
            count_low: row.fetch("count_low").to_i,
            total: row.fetch("total").to_i
          }
        end

        previous_page = offset <= page_size ? 0 : offset - page_size unless offset.zero?
        next_page = is_last_page ? nil : offset + page_size
        Result.new(
          alert_groups: group.finalize(alert_groups),
          previous: previous_page&.to_s,
          next: next_page&.to_s
        )
      end
    end
  end
end
