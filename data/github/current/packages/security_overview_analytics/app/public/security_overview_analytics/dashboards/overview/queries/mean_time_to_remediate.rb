# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alert_lifecycle_event_pb"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class MeanTimeToRemediate < Base
          class Result < T::Struct
            const :value, T.nilable(Float)
            const :alert_count, T.nilable(Integer)
          end

          RunQueryOutput = type_member { { fixed: Result } }

          private

          sig { override.returns(RunQueryOutput) }
          def query
            if return_alert_count
              res = ApplicationRecord::SecurityOverviewAnalytics.connection.select_one(%{
                SELECT
                  AVG(resolution_days) AS mttr,
                  COUNT(*) AS alert_count
                FROM (#{union_all_sql}) as combined_mttr
              }.squish)&.to_h

              return Result.new(value: res&.values.first.to_f || 0.to_f, alert_count: res&.values.second.round || 0)
            end

            sql = %{
              SELECT AVG(resolution_days) AS mttr
              FROM (#{union_all_sql}) as combined_mttr
            }.squish

            Result.new(value: ApplicationRecord::SecurityOverviewAnalytics.connection.select_value(sql)&.round.to_f || 0.to_f)
          end

          sig { override.returns(String) }
          def union_all_fallback_sql
            "SELECT NULL AS resolution_days WHERE FALSE"
          end

          sig { override.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
          def code_scanning_rel(slice4: nil)
            super.where("(#{CS_TABLE_NAME}.alert_resolution != #{RESOLUTIONS_CODE_SCANNING::FALSE_POSITIVE} OR #{CS_TABLE_NAME}.alert_resolution IS NULL)")
          end

          sig { override.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
          def dependabot_alerts_rel(slice4: nil)
            super.where("(#{DBOT_TABLE_NAME}.alert_resolution != #{RESOLUTIONS_DEPENDABOT_ALERTS::INACCURATE} OR #{DBOT_TABLE_NAME}.alert_resolution IS NULL)")
          end

          sig { override.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
          def secret_scanning_rel(slice4: nil)
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
