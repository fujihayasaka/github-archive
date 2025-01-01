# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AlertTrends::BySeverity < AlertTrends::Base
          RunQueryOutput = type_member { { fixed: RunQueryOutputAlias } }

          class Result < T::Struct
            include AlertTrends::Resultable

            prop :low, T::Array[AlertTrends::DataPoint], default: []
            prop :medium, T::Array[AlertTrends::DataPoint], default: []
            prop :high, T::Array[AlertTrends::DataPoint], default: []
            prop :critical, T::Array[AlertTrends::DataPoint], default: []

            sig { override.returns(AlertTrends::Base::RunQueryOutputAlias) }
            def to_h
              {
                "Low" => low.map { |r| r.to_h },
                "Medium" => medium.map { |r| r.to_h },
                "High" => high.map { |r| r.to_h },
                "Critical" => critical.map { |r| r.to_h }
              }
            end
          end

          private

          sig { params(union_all_sql_string: String).returns(String) }
          def generate_query(union_all_sql_string)
            %{
              SELECT
                date_id,
                SUM(revisions.low) AS low,
                SUM(revisions.medium) AS medium,
                SUM(revisions.high) AS high,
                SUM(revisions.critical) AS critical
              FROM (#{union_all_sql_string}) AS revisions
              GROUP BY date_id
              ORDER BY date_id
            }.squish
          end

          sig { override.params(offset: T.nilable(Integer), limit: T.nilable(Integer)).returns(RunQueryOutput) }
          def query(offset:, limit:)
            run_sliced_alert_revisions_query(accumulator: initialize_result,
              results_reducer: ->(accumulator, slice_result) {
                date = ::Date.parse(slice_result.fetch("date_id").to_s)

                accumulator.low.find { |r| r.x == date }.y += slice_result.fetch("low").round
                accumulator.medium.find { |r| r.x == date }.y += slice_result.fetch("medium").round
                accumulator.high.find { |r| r.x == date }.y += slice_result.fetch("high").round
                accumulator.critical.find { |r| r.x == date }.y += slice_result.fetch("critical").round

                accumulator
              }
            ) do |union_all_sql_string|
              generate_query(union_all_sql_string)
            end.to_h
          end

          sig { override.returns(String) }
          def union_all_fallback_sql
            %{
              SELECT
                NULL AS low,
                NULL AS medium,
                NULL AS high,
                NULL AS critical,
                NULL AS date_id
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
            rel
              .select("dates.id AS date_id")
              .joins("JOIN (#{dates_table_sql}) AS dates ON #{table_name}.next_revision_date_id > dates.id AND #{table_name}.date_id <= dates.id")
              .where(alert_resolved: !is_open_selected, repository_id: repo_metadata_rel.select(:repository_id))
              .group("dates.id")
              .order("dates.id")
          end

          sig { override.params(slice_by: T.nilable(SliceBy)).returns(ActiveRecord::Relation) }
          def code_scanning_rel(slice_by: nil)
            super
              .select(
                "COUNT(CASE WHEN alert_severity = 'low' THEN 1 END) AS low",
                "COUNT(CASE WHEN alert_severity = 'medium' THEN 1 END) AS medium",
                "COUNT(CASE WHEN alert_severity = 'high' THEN 1 END) AS high",
                "COUNT(CASE WHEN alert_severity = 'critical' THEN 1 END) AS critical"
              )
          end

          sig { override.params(slice_by: T.nilable(SliceBy)).returns(ActiveRecord::Relation) }
          def dependabot_alerts_rel(slice_by: nil)
            super
              .select(
                "COUNT(CASE WHEN alert_severity = 'low' THEN 1 END) AS low",
                "COUNT(CASE WHEN alert_severity = 'moderate' THEN 1 END) AS medium",
                "COUNT(CASE WHEN alert_severity = 'high' THEN 1 END) AS high",
                "COUNT(CASE WHEN alert_severity = 'critical' THEN 1 END) AS critical"
              )
          end

          sig { override.params(slice_by: T.nilable(SliceBy)).returns(ActiveRecord::Relation) }
          def secret_scanning_rel(slice_by: nil)
            super
              .select(
                "0 AS low",
                "0 AS medium",
                "0 AS high",
                "COUNT(*) AS critical"
              )
          end

          sig { returns(Result) }
          def initialize_result
            date_ids.each_with_object(Result.new) do |date_id, result|
              date = ::Date.parse(date_id.to_s)

              result.low << AlertTrends::DataPoint.new(x: date, y: 0)
              result.medium << AlertTrends::DataPoint.new(x: date, y: 0)
              result.high << AlertTrends::DataPoint.new(x: date, y: 0)
              result.critical << AlertTrends::DataPoint.new(x: date, y: 0)
            end
          end
        end
      end
    end
  end
end
