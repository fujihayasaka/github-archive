# typed: true
# frozen_string_literal: true

module Elastomer::Indexes
  class DependabotAlerts < ::Elastomer::Index
    def self.mappings_hook
      {
        repository_security_alert: {
          _all: { enabled: false },
          _routing: { required: true },

          properties: {
            # Shared fields
            repository_business_id: { type: "long" },
            repository_owner_id: { type: "long" },
            repository_owner_type: { type: "keyword" },
            repository_id: { type: "long" },

            # Repository metadata
            repository_name: { type: "keyword" },
            repository_visibility: { type: "keyword" },
            repository_archived: { type: "boolean" },
            dependabot_alerts_enabled: { type: "boolean" },
            code_scanning_enabled: { type: "boolean" },
            secret_scanning_enabled: { type: "boolean" },

            # Alert metadata

            ## Revision data
            alert_date_id: { type: "long" },
            alert_next_revision_date_id: { type: "long" },

            ## Common alert fields
            alert_feature_type: { type: "keyword" },
            alert_number: { type: "long" },
            alert_severity: { type: "keyword" }, # In-dev note: enum for better sorting
            alert_tool: { type: "keyword" },
            alert_resolved: { type: "boolean" },
            alert_resolution: { type: "keyword" },
            alert_created_at: { type: "date" },
            alert_updated_at: { type: "date" },
            alert_resolved_at: { type: "date" },
            alert_reopened_at: { type: "date" },

            ## Dependabot fields
            # In-dev note: importance for sorting
            dependabot_ghsa_id: { type: "keyword" },
            dependabot_package_name: { type: "keyword" },
            dependabot_ecosystem: { type: "keyword" },
            dependabot_dependency_scope: { type: "keyword" },

            ## Code scanning fields
            # alert_rule_sarif_identifier: { type: "keyword" },

            ## Secret-scanning fields
            # alert_token_type: { type: "keyword" },
            # alert_token_type_slug: { type: "keyword" },
            # alert_token_provider: { type: "keyword" },
            # alert_bypassed: { type: "boolean" },
            # alert_validity: { type: "integer" },
            # alert_validity_updated_at: { type: "date" },

            # Alerts can pull information from adjacent like vulnerabilities
            # which makes it difficult to rely on updated_at for running index repair jobs.
            # Any change in this signature means the alert payload should be reindexed.
            search_index_signature: { type: "binary" },

            # Join field
            repository_security_alert_join: {
              type: "join",
              relations: {
                repository: "security_alert"
              }
            }
          },
        }
      }
    end

    def self.settings_hook
      {
        index: {
          number_of_shards: GitHub.es_shard_count_for_dependabot_alerts,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          "queries.cache.enabled": true,
        },
      }
    end
  end
end
