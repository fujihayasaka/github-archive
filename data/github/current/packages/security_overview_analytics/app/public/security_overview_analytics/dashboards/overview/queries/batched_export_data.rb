# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class BatchedExportData < Base
          RunQueryOutput = type_member { { fixed: ActiveRecord::Relation } }

          private

          sig { override.returns(RunQueryOutput) }
          def query
            if security_features.include?("dependabot_alerts")
              return dependabot_alerts_rel if include_dependabot_alerts?
            elsif security_features.include?("secret_scanning")
              return secret_scanning_rel if include_secret_scanning?
            elsif !security_features.size.zero?
              return code_scanning_rel if include_code_scanning?
            else
              raise "There are no security features to get alert data from"
            end

            T.cast([], ActiveRecord::Relation)
          end

          sig { override.params(slice_by: T.nilable(SliceBy)).returns(ActiveRecord::Relation) }
          def secret_scanning_rel(slice_by: nil)
            secret_scanning_selections = [
              "'secret-scanning' AS tool",
              "'critical' AS alert_severity",
              "`#{SS_TABLE_NAME}`.`alert_bypassed`",
              "`#{SS_TABLE_NAME}`.`alert_type`",
              "`#{SS_TABLE_NAME}`.`alert_type_provider`",
              "`#{SS_TABLE_NAME}`.`alert_validity`",
              "NULL AS ghsa_id",
              "NULL AS ecosystem",
              "NULL AS package_name",
              "NULL AS dependency_scope",
              "NULL AS rule_sarif_identifier",
            ]

            super
              .select("#{(universal_selections(SS_TABLE_NAME) + secret_scanning_selections).join(", ")}")
          end

          sig { override.params(slice_by: T.nilable(SliceBy)).returns(ActiveRecord::Relation) }
          def code_scanning_rel(slice_by: nil)
            code_scanning_selections = [
              "`#{CS_TABLE_NAME}`.`tool`",
              "`#{CS_TABLE_NAME}`.`alert_severity`",
              "NULL AS alert_bypassed",
              "NULL AS alert_type",
              "NULL AS alert_type_provider",
              "NULL AS alert_validity",
              "NULL AS ghsa_id",
              "NULL AS ecosystem",
              "NULL AS package_name",
              "NULL AS dependency_scope",
              "`#{CS_TABLE_NAME}`.`rule_sarif_identifier`",
            ]

            super
              .select("#{(universal_selections(CS_TABLE_NAME) + code_scanning_selections).join(", ")}")
          end

          sig { override.params(slice_by: T.nilable(SliceBy)).returns(ActiveRecord::Relation) }
          def dependabot_alerts_rel(slice_by: nil)
            dependabot_selections = [
              "'dependabot' AS tool",
              "`#{DBOT_TABLE_NAME}`.`alert_severity`",
              "NULL AS alert_bypassed",
              "NULL AS alert_type",
              "NULL AS alert_type_provider",
              "NULL AS alert_validity",
              "`#{DBOT_TABLE_NAME}`.`ghsa_id`",
              "`#{DBOT_TABLE_NAME}`.`ecosystem`",
              "`#{DBOT_TABLE_NAME}`.`package_name`",
              "`#{DBOT_TABLE_NAME}`.`dependency_scope`",
              "NULL AS rule_sarif_identifier",
            ]

            super
              .select("#{(universal_selections(DBOT_TABLE_NAME) + dependabot_selections).join(", ")}")
          end

          sig { override.returns(String) }
          def union_all_fallback_sql
            %{
              SELECT
                NULL AS repository_id,
                NULL AS name,
                NULL AS visibility,
                NULL AS alert_number,
                NULL AS alert_created_at,
                NULL AS alert_updated_at,
                NULL AS alert_resolved_at,
                NULL AS alert_reopened_at,
                NULL AS alert_resolution
              FROM DUAL
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
            if SecurityCenter::FeatureFlagHelper.overview_export_use_inner_query?(scope, user)
              inner_rel = rel
                .where(repository_id: repo_metadata_rel.select(:repository_id))
                .where("`#{rel.table_name}`.`next_revision_date_id` > ?", end_date_id)
                .where("`#{rel.table_name}`.`date_id` <= ?", end_date_id)
                .select(:id)


              rel.klass.all
                .joins("JOIN #{::SecurityOverviewAnalytics::Repository.table_name} AS repos ON #{table_name}.repository_id = repos.repository_id")
                .where("`#{table_name}`.`id` IN (#{inner_rel.to_sql})")
            else
              rel
                .joins("JOIN #{::SecurityOverviewAnalytics::Repository.table_name} AS repos ON #{table_name}.repository_id = repos.repository_id")
                .where(repository_id: repo_metadata_rel.select(:repository_id))
                .where("`#{rel.table_name}`.`next_revision_date_id` > ?", end_date_id)
                .where("`#{rel.table_name}`.`date_id` <= ?", end_date_id)
            end
          end

          sig { params(table_name: String).returns(T::Array[String]) }
          def universal_selections(table_name)
            [
              "`#{table_name}`.`id` AS id",
              "repos.repository_id",
              "repos.name",
              "repos.visibility",
              "`#{table_name}`.`alert_number`",
              "`#{table_name}`.`alert_created_at`",
              "`#{table_name}`.`alert_updated_at`",
              "`#{table_name}`.`alert_resolved_at`",
              "`#{table_name}`.`alert_reopened_at`",
              "`#{table_name}`.`alert_resolution`",
            ]
          end
        end
      end
    end
  end
end
