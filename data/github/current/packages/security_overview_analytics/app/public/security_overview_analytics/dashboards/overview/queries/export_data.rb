# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class ExportData < Base
          RunQueryOutput = type_member { { fixed: T::Array[T.untyped] } }

          UNIVERSAL_SELECTIONS = T.let(
            %w[
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
            # TODO: we will need to batch this https://github.com/github/security-center/issues/5049
            fields_to_values = ApplicationRecord::SecurityOverviewAnalytics.connection.select_all(union_all_sql).map(&:to_h)

            if fields_to_values.present?
              # TODO make this work at the business level
              team_id_to_slug = T.cast(scope, Organization)
                .visible_teams_for(user, fields: [:id, :slug])
                .pluck(:id, :slug)
                .to_h

              repo_ids = fields_to_values.map { |row| row["repository_id"] }.uniq
              topic_names_by_repository_id = SecurityCenter::Export::DataQuery.get_topics_by_repository_id(repo_ids)
              teams_by_repository_id = SecurityCenter::Export::DataQuery.get_teams_by_repository_id(repo_ids, team_id_to_slug, scope, 1)

              repos = ::Repository.where(id: repo_ids)
              property_values_by_repo = CustomProperties::Public.repo_properties(repos, :effective)
              props_by_repo_id = property_values_by_repo.transform_keys(&:id)

              fields_to_values.each do |row|
                row["teams"] = teams_by_repository_id[row["repository_id"]] || []
                row["repo_properties"] = props_by_repo_id[row["repository_id"]]&.with_indifferent_access || []
                row["repo_topics"] = topic_names_by_repository_id[row["repository_id"]] || []
              end
            end

            fields_to_values || []
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
