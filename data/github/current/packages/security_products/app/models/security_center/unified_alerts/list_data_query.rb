# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module UnifiedAlerts
    class ListDataQuery < DataQuery
      extend T::Sig
      include GitHub::SecurityCenter::TenantFilteringHelper
      include AlertDataLoader

      # Number of alert per page. Grouped or ungrouped
      DEFAULT_PAGE_SIZE = 25

      AlertData = T.type_alias { T::Hash[Symbol, T.untyped] }

      class Result < T::Struct
        const :alerts, T::Array[AlertData]
        const :previous, T.nilable(String)
        const :next, T.nilable(String)
      end

      sig { params(cursor: String, page_size: Integer).returns(Result) }
      def run(cursor: "0", page_size: DEFAULT_PAGE_SIZE)
        offset = T.let(Integer(cursor, exception: false), T.nilable(Integer))
        raise ArgumentError, "Unexpected `cursor` input." if offset.nil? || offset < 0

        return Result.new(alerts: []) if page_size <= 0

        limit = page_size + 1 # To know if it is the last page
        subquery_limit = offset + limit
        severity_order = %{CASE `alert_severity`
          WHEN NULL THEN 0
          WHEN 'LOW' THEN 1
          WHEN 'MEDIUM' THEN 2
          WHEN 'HIGH' THEN 3
          WHEN 'CRITICAL' THEN 4
          END desc}.squish

        union_all_query_parts = T.let([], T::Array[String])
        security_features.each do |feature|
          feature_base_rel = security_feature_base_rel(feature)
          next if feature_base_rel.nil?

          feature_module = T.must(SECURITY_FEATURE_MODEL_MAPPINGS[feature])
          alert_severity_type_column = if feature == SecurityFeatures::SECRET_SCANNING
            "'CRITICAL' as `alert_severity`"
          else
            "IF(`#{feature_module.table_name}`.`alert_severity` = 'MODERATE', 'MEDIUM', `#{feature_module.table_name}`.`alert_severity`) AS `alert_severity`"
          end
          alert_feature_type_column = "'#{feature}' AS feature_type"
          union_all_query_parts << "(#{
            feature_base_rel
              .order(Arel.sql(severity_order), alert_created_at: :desc, id: :desc)
              .limit(subquery_limit)
              .select(
                :alert_created_at,
                :repository_id,
                :alert_number,
                Arel.sql(alert_severity_type_column),
                Arel.sql(alert_feature_type_column),
                :id
              )
              .to_sql
          })"
        end
        return Result.new(alerts: []) if union_all_query_parts.empty?

        unified_alerts = union_all_query_parts.join(" UNION ALL ")
        full_sql = %{
          SELECT feature_type, id AS alert_revision_id, alert_number, alert_severity, repository_id
          FROM (#{unified_alerts}) AS unified
          ORDER BY #{Arel.sql(severity_order)}, alert_created_at DESC, alert_revision_id DESC, feature_type ASC
          LIMIT #{limit} OFFSET #{offset}
        }.squish

        alerts = T.let([], T::Array[AlertData])
        is_last_page = T.let(true, T::Boolean)
        ApplicationRecord::SecurityOverviewAnalytics.connection.select_all(full_sql).each_with_index do |row, index|
          if index >= page_size
            is_last_page = false
            next # Skip alert after page_size limit
          end

          alerts << {
            feature_type: row.fetch("feature_type"),
            alert_revision_id: row.fetch("alert_revision_id")&.to_i,
            alert_number: row.fetch("alert_number")&.to_i,
            alert_severity: row.fetch("alert_severity"),
            repository_id: row.fetch("repository_id")&.to_i,
          }
        end

        alerts = filter_tenant_rows(
          RequestScope.new(:organization, scope, "unified_alerts"),
          alerts,
          -> (alert) { alert[:repository_id] }
        ).first

        hydrate_alerts_data!(alerts)

        previous_page = offset <= page_size ? 0 : offset - page_size unless offset.zero?
        next_page = is_last_page ? nil : offset + page_size
        Result.new(alerts: alerts, previous: previous_page&.to_s, next: next_page&.to_s)
      end
    end
  end
end
