# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AlertTrends::ByAge < AlertTrends::Base
          RunQueryOutput = type_member { { fixed: RunQueryOutputAlias } }

          class Result < T::Struct
            include AlertTrends::Resultable

            prop :less_than_thirty_days_old, T::Array[AlertTrends::DataPoint], default: []
            prop :thirty_to_fifty_nine_days_old, T::Array[AlertTrends::DataPoint], default: []
            prop :sixty_to_eighty_nine_days_old, T::Array[AlertTrends::DataPoint], default: []
            prop :ninety_plus_days_old, T::Array[AlertTrends::DataPoint], default: []

            sig { override.returns(AlertTrends::Base::RunQueryOutputAlias) }
            def to_h
              {
                "< 30 days" => less_than_thirty_days_old.map { |r| r.to_h },
                "31 - 59 days" => thirty_to_fifty_nine_days_old.map { |r| r.to_h },
                "60 - 89 days" => sixty_to_eighty_nine_days_old.map { |r| r.to_h },
                "90+ days" => ninety_plus_days_old.map { |r| r.to_h }
              }
            end
          end

          private

          sig { params(union_all_sql_string: String).returns(String) }
          def generate_query(union_all_sql_string)
            numerator = is_open_selected ? "date_id" : "alert_resolved_at"

            %{
              SELECT
                date_id,
                COALESCE(SUM(CASE WHEN DATEDIFF(#{numerator}, revisions.alert_created_at) < 30 THEN 1 ELSE 0 END), 0) AS less_than_thirty_days_old,
                COALESCE(SUM(CASE WHEN DATEDIFF(#{numerator}, revisions.alert_created_at) BETWEEN 30 AND 59 THEN 1 ELSE 0 END), 0) AS thirty_to_fifty_nine_days_old,
                COALESCE(SUM(CASE WHEN DATEDIFF(#{numerator}, revisions.alert_created_at) BETWEEN 60 AND 89 THEN 1 ELSE 0 END), 0) AS sixty_to_eighty_nine_days_old,
                COALESCE(SUM(CASE WHEN DATEDIFF(#{numerator}, revisions.alert_created_at) >= 90 THEN 1 ELSE 0 END), 0) AS ninety_plus_days_old
              FROM (#{union_all_sql_string}) AS revisions
              GROUP BY date_id
              ORDER BY date_id
            }.squish
          end

          sig { override.returns(RunQueryOutput) }
          def query
            run_sliced_alert_revisions_query(accumulator: initialize_result,
              results_reducer: ->(accumulator, slice_result) {
                date = ::Date.parse(slice_result.fetch("date_id").to_s)

                accumulator.less_than_thirty_days_old.find { |r| r.x == date }.y += slice_result.fetch("less_than_thirty_days_old").round
                accumulator.thirty_to_fifty_nine_days_old.find { |r| r.x == date }.y += slice_result.fetch("thirty_to_fifty_nine_days_old").round
                accumulator.sixty_to_eighty_nine_days_old.find { |r| r.x == date }.y += slice_result.fetch("sixty_to_eighty_nine_days_old").round
                accumulator.ninety_plus_days_old.find { |r| r.x == date }.y += slice_result.fetch("ninety_plus_days_old").round

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
                NULL AS alert_created_at,
                NULL AS alert_resolved_at,
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
              .select(
                :next_revision_date_id,
                :alert_created_at,
                :alert_resolved_at,
                "dates.id AS date_id"
              )
              .joins("JOIN (#{dates_table_sql}) AS dates ON #{table_name}.next_revision_date_id > dates.id AND #{table_name}.date_id <= dates.id")
              .where(
                alert_resolved: !is_open_selected,
                repository_id: repo_metadata_rel.select(:repository_id)
              )
          end

          sig { returns(Result) }
          def initialize_result
            date_ids.each_with_object(Result.new) do |date_id, result|
              date = ::Date.parse(date_id.to_s)

              result.less_than_thirty_days_old << AlertTrends::DataPoint.new(x: date, y: 0)
              result.thirty_to_fifty_nine_days_old << AlertTrends::DataPoint.new(x: date, y: 0)
              result.sixty_to_eighty_nine_days_old << AlertTrends::DataPoint.new(x: date, y: 0)
              result.ninety_plus_days_old << AlertTrends::DataPoint.new(x: date, y: 0)
            end
          end
        end
      end
    end
  end
end
