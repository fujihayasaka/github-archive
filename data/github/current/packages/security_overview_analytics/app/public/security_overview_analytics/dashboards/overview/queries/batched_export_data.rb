# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class BatchedExportData < Base
          RunQueryOutput = type_member { { fixed: ActiveRecord::Relation } }

          UNIVERSAL_SELECTIONS = T.let(
            %w[
              id
              repos.repository_id
              repos.name
              repos.visibility
              repos.archived
              alert_number
              alert_created_at
              alert_updated_at
              alert_resolved_at
              alert_reopened_at
              alert_resolution
            ],
            T::Array[String]
          )

          private

          sig { override.returns(RunQueryOutput) }
          def query
            security_feature = if security_features.include?("dependabot_alerts")
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

          sig { override.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
          def secret_scanning_rel(slice4: nil)
            secret_scanning_selections = [
              "'secret-scanning' AS tool",
              "'critical' AS alert_severity",
              "alert_bypassed",
              "alert_type",
              "alert_type_provider",
              "alert_validity",
              "NULL AS ghsa_id",
              "NULL AS ecosystem",
              "NULL AS package_name",
              "NULL AS dependency_scope",
              "NULL AS rule_sarif_identifier",
            ]

            super
              .select("#{(UNIVERSAL_SELECTIONS + secret_scanning_selections).join(", ")}")
          end

          sig { override.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
          def code_scanning_rel(slice4: nil)
            code_scanning_selections = [
              "tool",
              "alert_severity",
              "NULL AS alert_bypassed",
              "NULL AS alert_type",
              "NULL AS alert_type_provider",
              "NULL AS alert_validity",
              "NULL AS ghsa_id",
              "NULL AS ecosystem",
              "NULL AS package_name",
              "NULL AS dependency_scope",
              "rule_sarif_identifier",
            ]

            super
              .select("#{(UNIVERSAL_SELECTIONS + code_scanning_selections).join(", ")}")
          end

          sig { override.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
          def dependabot_alerts_rel(slice4: nil)
            dependabot_selections = [
              "'dependabot' AS tool",
              "alert_severity",
              "NULL AS alert_bypassed",
              "NULL AS alert_type",
              "NULL AS alert_type_provider",
              "NULL AS alert_validity",
              "ghsa_id",
              "ecosystem",
              "package_name",
              "dependency_scope",
              "NULL AS rule_sarif_identifier",
            ]

            super
              .select("#{(UNIVERSAL_SELECTIONS + dependabot_selections).join(", ")}")
          end

          sig { override.returns(String) }
          def union_all_fallback_sql
            %{
              SELECT
                NULL AS repository_id,
                NULL AS name,
                NULL AS visibility,
                NULL AS archived,
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
              .joins("JOIN #{::SecurityOverviewAnalytics::Repository.table_name} AS repos ON #{table_name}.repository_id = repos.repository_id")
              .where(repository_id: repo_metadata_rel.select(:repository_id))
              .where("next_revision_date_id > ?", end_date_id)
              .where("date_id <= ?", end_date_id)
          end
        end
      end
    end
  end
end
