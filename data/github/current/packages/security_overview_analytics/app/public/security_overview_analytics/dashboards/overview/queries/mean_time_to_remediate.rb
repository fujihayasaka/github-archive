# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alert_lifecycle_event_pb"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class MeanTimeToRemediate < Base
          class Result < T::Struct
            prop :value, T.nilable(Float), default: 0.0
            prop :alert_count, T.nilable(Integer), default: 0
          end

          RunQueryOutput = type_member { { fixed: Result } }

          private

          sig { params(union_all_sql_string: String).returns(String) }
          def generate_query(union_all_sql_string)
            %{
              SELECT
                AVG(resolution_days) AS mttr,
                COUNT(*) AS alert_count
              FROM (#{union_all_sql_string}) as combined_mttr
            }.squish
          end

          sig { override.params(offset: T.nilable(Integer), limit: T.nilable(Integer)).returns(RunQueryOutput) }
          def query(offset:, limit:)
            result = run_sliced_alert_revisions_query(accumulator: SingleValueAccumulator.new, results_reducer: avg_reducer(data_column: :mttr, count_column: :alert_count)) do |union_all_sql_string|
              generate_query(union_all_sql_string)
            end

            Result.new(value: result.value, alert_count: result.alert_count)
          end

          sig { override.returns(String) }
          def union_all_fallback_sql
            "SELECT NULL AS resolution_days WHERE FALSE"
          end

          sig { override.params(slice_by: T.nilable(SliceBy)).returns(ActiveRecord::Relation) }
          def code_scanning_rel(slice_by: nil)
            super.where("(#{CS_TABLE_NAME}.alert_resolution != #{RESOLUTIONS_CODE_SCANNING::FALSE_POSITIVE} OR #{CS_TABLE_NAME}.alert_resolution IS NULL)")
          end

          sig { override.params(slice_by: T.nilable(SliceBy)).returns(ActiveRecord::Relation) }
          def dependabot_alerts_rel(slice_by: nil)
            super.where("(#{DBOT_TABLE_NAME}.alert_resolution != #{RESOLUTIONS_DEPENDABOT_ALERTS::INACCURATE} OR #{DBOT_TABLE_NAME}.alert_resolution IS NULL)")
          end

          sig { override.params(slice_by: T.nilable(SliceBy)).returns(ActiveRecord::Relation) }
          def secret_scanning_rel(slice_by: nil)
            super.where("(#{SS_TABLE_NAME}.alert_resolution != #{RESOLUTIONS_SECRET_SCANNING::FALSE_POSITIVE} OR #{SS_TABLE_NAME}.alert_resolution IS NULL)")
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
              .select(%{
                (
                  DATEDIFF(
                    CAST(#{table_name}.alert_resolved_at AS DATE),
                    CAST(#{table_name}.alert_created_at AS DATE)
                  ) + 1
                ) AS resolution_days
              }.squish)
              .where(
                alert_resolved: true,
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
