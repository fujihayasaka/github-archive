# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class BatchedExportData < Base
          DEFAULT_OFFSET = 0
          DEFAULT_LIMIT = 2500

          RunQueryOutput = type_member { { fixed: ActiveRecord::Relation } }

          private

          sig { override.params(offset: T.nilable(Integer), limit: T.nilable(Integer)).returns(RunQueryOutput) }
          def query(offset:, limit:)
            offset ||= DEFAULT_OFFSET
            limit ||= DEFAULT_LIMIT

            if include_dependabot_alerts?
              query_dependabot_alerts(offset:, limit:)
            elsif include_secret_scanning?
              query_secret_scanning(offset:, limit:)
            elsif include_code_scanning?
              query_code_scanning(offset:, limit:)
            else
              raise "There are no security features to get alert data from"
            end
          end

          sig { params(offset: Integer, limit: Integer).returns(ActiveRecord::Relation) }
          def query_secret_scanning(offset:, limit:)
            output_columns = universal_selections(SS_TABLE_NAME) + [
              "'secret-scanning' AS `tool`",
              "'critical' AS `alert_severity`",
              "`#{SS_TABLE_NAME}`.`alert_bypassed`",
              "`#{SS_TABLE_NAME}`.`alert_type`",
              "`#{SS_TABLE_NAME}`.`alert_type_provider`",
              "`#{SS_TABLE_NAME}`.`alert_validity`",
              "NULL AS `ghsa_id`",
              "NULL AS `ecosystem`",
              "NULL AS `package_name`",
              "NULL AS `dependency_scope`",
              "NULL AS `rule_sarif_identifier`",
            ]

            inner_rel = secret_scanning_rel
              .select("`#{SS_TABLE_NAME}`.`id` AS `id`")
              .where(id: (offset + 1)..)
              .order(:id)
              .limit(limit)

            inner_rel
              .klass
              .select("#{output_columns.join(", ")}")
              .joins("JOIN (#{inner_rel.to_sql}) AS `revisions` ON `#{SS_TABLE_NAME}`.`id` = `revisions`.`id` ")
              .joins("JOIN `#{::SecurityOverviewAnalytics::Repository.table_name}` AS `repos` ON `#{SS_TABLE_NAME}`.`repository_id` = `repos`.`repository_id`")
              .order(:id)
          end

          sig { params(offset: Integer, limit: Integer).returns(ActiveRecord::Relation) }
          def query_code_scanning(offset:, limit:)
            output_columns = universal_selections(CS_TABLE_NAME) + [
              "`#{CS_TABLE_NAME}`.`tool`",
              "`#{CS_TABLE_NAME}`.`alert_severity`",
              "NULL AS `alert_bypassed`",
              "NULL AS `alert_type`",
              "NULL AS `alert_type_provider`",
              "NULL AS `alert_validity`",
              "NULL AS `ghsa_id`",
              "NULL AS `ecosystem`",
              "NULL AS `package_name`",
              "NULL AS `dependency_scope`",
              "`#{CS_TABLE_NAME}`.`rule_sarif_identifier`",
            ]

            inner_rel = code_scanning_rel
              .select("`#{CS_TABLE_NAME}`.`id` AS `id`")
              .where(id: (offset + 1)..)
              .order(:id)
              .limit(limit)

            inner_rel
              .klass
              .select("#{output_columns.join(", ")}")
              .joins("JOIN (#{inner_rel.to_sql}) AS `revisions` ON `#{CS_TABLE_NAME}`.`id` = `revisions`.`id` ")
              .joins("JOIN `#{::SecurityOverviewAnalytics::Repository.table_name}` AS `repos` ON `#{CS_TABLE_NAME}`.`repository_id` = `repos`.`repository_id`")
              .order(:id)
          end

          sig { params(offset: Integer, limit: Integer).returns(ActiveRecord::Relation) }
          def query_dependabot_alerts(offset:, limit:)
            output_columns = universal_selections(DBOT_TABLE_NAME) + [
              "'dependabot' AS `tool`",
              "`#{DBOT_TABLE_NAME}`.`alert_severity`",
              "NULL AS `alert_bypassed`",
              "NULL AS `alert_type`",
              "NULL AS `alert_type_provider`",
              "NULL AS `alert_validity`",
              "`#{DBOT_TABLE_NAME}`.`ghsa_id`",
              "`#{DBOT_TABLE_NAME}`.`ecosystem`",
              "`#{DBOT_TABLE_NAME}`.`package_name`",
              "`#{DBOT_TABLE_NAME}`.`dependency_scope`",
              "NULL AS `rule_sarif_identifier`",
            ]

            inner_rel = dependabot_alerts_rel
              .select("`#{DBOT_TABLE_NAME}`.`id` AS `id`")
              .where(id: (offset + 1)..)
              .order(:id)
              .limit(limit)

            inner_rel
              .klass
              .select("#{output_columns.join(", ")}")
              .joins("JOIN (#{inner_rel.to_sql}) AS `revisions` ON `#{DBOT_TABLE_NAME}`.`id` = `revisions`.`id` ")
              .joins("JOIN `#{::SecurityOverviewAnalytics::Repository.table_name}` AS `repos` ON `#{DBOT_TABLE_NAME}`.`repository_id` = `repos`.`repository_id`")
              .order(:id)
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
            rel
              .where(repository_id: repo_metadata_rel.select(:repository_id))
              .where("`#{rel.table_name}`.`next_revision_date_id` > ?", end_date_id)
              .where("`#{rel.table_name}`.`date_id` <= ?", end_date_id)
          end

          sig { params(table_name: String).returns(T::Array[String]) }
          def universal_selections(table_name)
            [
              "`#{table_name}`.`id` AS `id`",
              "`repos`.`repository_id`",
              "`repos`.`name`",
              "`repos`.`visibility`",
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
