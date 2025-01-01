# typed: true
# frozen_string_literal: true

module Elastomer::Indexes

  # The AuditLog index contains documents for audit log entries. These documents
  # are searchable within this index.
  class AuditLog < ::Elastomer::Index
    # The Lucene limit for each indexable field is 32,766 bytes. Since
    # we support emojis and emojis can be 4 bytes we need to make sure we can
    # fit all characters. 32,766 / 4 = 8,191
    IGNORE_ABOVE_LIMIT = 8191

    def self.slicer
      ::Elastomer::Slicers::AuditLogDateSlicer.new(index: self)
    end

    def self.sliced?
      true
    end

    # Defines the mappings for the 'audit_entry' document type.
    #
    # Returns the Hash containing the document type mappings.
    def self.mappings_hook
      {
        audit_entry: {
          _all: { enabled: false },
          dynamic: false,
          dynamic_templates: [
            {
              strings: {
                match_mapping_type: "string",
                mapping: { type: "string", index: "not_analyzed", ignore_above: IGNORE_ABOVE_LIMIT }
              }
            }
          ],
          properties: {
            "@timestamp": { type: "date" },
            operation_type: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
            actor_id: { type: "long" },
            actor: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
            business: { type: "text", analyzer: "lowercase" },
            business_id: { type: "long" },
            staff_actor: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
            staff_actor_id: { type: "long" },
            oauth_app_id: { type: "long" },
            action: {
              type: "text",
              norms: false,
              analyzer: "action",
              search_analyzer: "keyword",
              index_options: "docs"
            },
            user_id: { type: "long" },
            user: { type: "text", analyzer: "lowercase" },
            repo_id: { type: "long" },
            repo: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
            actor_ip: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
            actor_location: {
              properties: {
                country_code: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                country_code3: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                country_name: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                region: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                region_name: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                city: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                postal_code: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                location: { type: "geo_point" },
                dma_code: { type: "long" },
                area_code: { type: "long" }
              }
            },
            created_at: { type: "date" },
            from: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
            note: { type: "text" },
            org: { type: "text", analyzer: "lowercase" },
            org_id: { type: "long" },
            device_cookie: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
            raw_data: { type: "text" },
            data: {
              type: "object",
              dynamic: true,
              properties: {
                workflow_id: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                id: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                oauth_scopes: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                application_name: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                scopes: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                team: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                title: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                transfer_from: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                transfer_to: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                visibility: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                access: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                public_key_id: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                key: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                fingerprint: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                auth: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                token: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                card_transactions: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                request_method: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                old_name: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                old_login: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                old_user: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                state: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                error: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                error_messages: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                reason: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                email: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                fork_source: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                fork_parent: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                query_string: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                name: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                actor_session: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                transaction_id: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                controller: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                version: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                request_id: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                plan: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                ip_address: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                pull_request: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                owners: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                disabling_reason: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                gist_id: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                oauth_access_id: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                application_id: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                team_id: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                oauth_application_id: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                issue_id: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                issue_comment_id: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                key_repo_id: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                key_user_id: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                old_user_id: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                comment_id: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                subject_id: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                two_factor: { type: "boolean" },
                ldap_mapped: { type: "boolean" },
                successful: { type: "boolean" },
                whitelist: { type: "boolean" },
                disabled_at: { type: "date" },
                disabled_by: { type: "object", enabled: "false" },
                enabled_by: { type: "object", enabled: "false" },
                change: { type: "object", enabled: "false" },
                gist: { type: "object", enabled: "false" },
                timing: {
                  properties: {
                    start: { type: "long" },
                    end: { type: "long" },
                    duration: { type: "float" }
                  }
                },
                _invalid: { type: "boolean" },
                _invalid_actor: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                _invalid_reason: { type: "keyword", ignore_above: IGNORE_ABOVE_LIMIT },
                _invalid_at: { type: "date" }
              }
            }
          }
        }
      }
    end

    # Settings for an AuditLog search index.
    #
    # Returns the Hash containing the settings for this index.
    def self.settings_hook
      {
        index: {
          mapper: {
            dynamic: false,
          },
          number_of_shards: GitHub.es_shard_count_for_audit_log,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          translog: {
            durability: "request",
          },
        },
        analysis: {
          analyzer: {
            action: {
              type: "custom",
              tokenizer: "action_path",
            },
            lowercase: {
              tokenizer: "whitespace",
              filter: %w[lowercase],
            },
          },
          tokenizer: {
            action_path: {
              type: "path_hierarchy",
              delimiter: ".",
            },
          },
        },
      }
    end

    # Initialize a new AuditLog index.
    #
    # name    - The index name as a String or Symbol
    # cluster - The cluster name as a String or Symbol
    #
    def initialize(name = nil, cluster = nil)
      name = self.class.index_name if name.nil?
      cluster = GitHub.es_audit_log_cluster if cluster.nil?

      super(name, cluster)
    end

    # Internal: Builds the request body for updating the index template with the
    # index's settings and mappings.
    #
    # Returns Hash.
    def template_data
      if Rails.env.test?
        super.merge(order: 1, aliases: {})
      else
        super.merge \
          order: 4,
          aliases: { self.class.logical_index_name => {} }
      end
    end

  end  # AuditLog
end  # Elastomer::Indexes
