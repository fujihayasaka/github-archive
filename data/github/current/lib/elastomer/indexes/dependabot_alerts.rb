# typed: true
# frozen_string_literal: true

module Elastomer::Indexes
  class DependabotAlerts < ::Elastomer::Index
    def self.mappings_hook
      {
        dependabot_alert: {
          _all: { enabled: false },
          _routing: { required: true },

          properties: {
            # Unified risk metadata for Dependabot alerts.
            risk_type: { type: "constant_keyword" },

            # Immutable foreign keys
            repository_id: { type: "long" },
            vulnerability_id: { type: "long" },
            vulnerable_version_range_id: { type: "long" },

            # Mutable foreign keys
            owner_id: { type: "long" },

            # Immutable external data
            ecosystem: { type: "keyword" },
            package_name: { type: "keyword" },

            # Immutable internal data
            id: { type: "long" },
            created_at: { type: "date" },
            manifest_path: {
              type: "text",
              fields: {
                filter: { type: "text", analyzer: "path_hierarchy" }
              },
              analyzer: "path_split"
            },
            relationship: { type: "keyword" },

            # Mutable external data
            severity: { type: "keyword" },
            severity_score: { type: "scaled_float", scaling_factor: 10 },
            has_patch: { type: "boolean" },
            epss_percentage: { type: "scaled_float", scaling_factor: 100 },
            description: { type: "text", analyzer: "texty" },
            summary: { type: "text", analyzer: "texty" },

            # Mutable internal data
            dependency_scope: { type: "keyword" },
            state: { type: "keyword" },
            resolution: { type: "keyword" },
            last_state_change_at: { type: "date" },
            updated_at: { type: "date" },
            search_index_updated_at: { type: "date" },
          },
        },
      }
    end

    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_dependabot_alerts,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          "queries.cache.enabled": true,
        },
        analysis: {
          analyzer: {
            path_hierarchy: {
              tokenizer: "path_hierarchy",
              filter: "lowercase",
            },
            path_split: {
              type: "custom",
              tokenizer: "path_split",
              filter: "lowercase",
            },
            title: {
              tokenizer: "standard",
              filter: %w[lowercase asciifolding],
            },
            tag_name: {
              type: "custom",
              tokenizer: "tag_name",
              filter: %w[lowercase],
            },
          },
          tokenizer: {
            path_split: {
              type: "pattern",
              pattern: "/",
            },
            # Tokenize tag names like "v1.2.0" so we can search by v1, v1.2, v1.2.0.
            tag_name: {
              type: "path_hierarchy",
              delimiter: ".",
            },
          },
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      settings
    end

    # Wraps Elastomer::Index#store to gather metrics on storing alerts.
    #
    # adapter - An Adapter instance
    # params  - Parameters Hash
    #
    # Returns the response body as a Hash.
    def store(adapter, params = {})
      response = super
      return response if response.nil?

      bulk_items = response.fetch("items", nil)
      if bulk_items.nil?
        # single document response.  Failures from calls in this flow
        # will be raised as errors and handled by the rescue block.
        GitHub.dogstats.increment(
          "dependabot_alerts.search.index",
          tags: ["action:index", "adapter:#{adapter.class.name.demodulize}"]
        )
        return response
      end

      # bulk document response. Failures from individual operations will be
      # returned inline in the response.
      results_by_action = Hash.new { |h, k| h[k] = { success: 0, failed: 0 } }
      bulk_items.each do |item|
        item.each do |action, item_response|
          if (200...300).cover?(item_response.fetch("status"))
            results_by_action[action][:success] += 1
          else
            results_by_action[action][:failed] += 1
          end
        end
      end

      results_by_action.each do |action, results|
        if results[:success] > 0
          GitHub.dogstats.count(
            "dependabot_alerts.search.index",
            results[:success],
            tags: ["action:#{action}", "adapter:#{adapter.class.name.demodulize}"]
          )
        end
        if results[:failed] > 0
          GitHub.dogstats.count(
            "dependabot_alerts.search.index.error",
            results[:failed],
            tags: ["action:#{action}", "adapter:#{adapter.class.name.demodulize}"]
          )
        end
      end

      response
    rescue ElastomerClient::Client::Error
      # In the case of a client error, we treat the failure like a
      # single document request because we don't have any information to
      # determine the count of failures for a bulk document request
      GitHub.dogstats.increment(
        "dependabot_alerts.search.index.error",
        tags: ["action:index", "adapter:#{adapter.class.name.demodulize}"]
      )
      raise
    end

    # Wraps Elastomer::Index#remove to gather metrics on removing
    # alerts from the search index.
    #
    # adapter - An Adapter instance
    #
    # Returns the response body as a Hash.
    def remove(adapter)
      response = super
      return response if response.nil?

      total_count = response.fetch("total", nil)
      if total_count.nil?
        # single delete response. Failures from calls in this flow
        # will be raised as errors and handled by the rescue block.
        GitHub.dogstats.increment(
          "dependabot_alerts.search.index",
          tags: ["action:delete", "adapter:#{adapter.class.name.demodulize}"]
        )
        return response
      end

      # bulk delete response.  Failures from individual operations will be
      # determined based on the counts in the response.
      deleted_count = response.fetch("deleted")
      GitHub.dogstats.count(
        "dependabot_alerts.search.index",
        deleted_count,
        tags: ["action:delete", "adapter:#{adapter.class.name.demodulize}"]
      )

      if deleted_count < total_count
        GitHub.dogstats.count(
         "dependabot_alerts.search.index.error",
          total_count - deleted_count,
          tags: ["action:delete", "adapter:#{adapter.class.name.demodulize}"]
        )
      end

      response
    rescue ElastomerClient::Client::Error
      # In the case of a client error, we treat the failure like a
      # single document request because we don't have any information to
      # determine the count of failures for a bulk document request
      GitHub.dogstats.increment(
        "dependabot_alerts.search.index.error",
        tags: ["action:delete", "adapter:#{adapter.class.name.demodulize}"]
      )
      raise
    end

    def self.searcher(name = ::Elastomer.env.index_name("dependabot-alerts"), cluster = nil)
      if cluster.nil? && name.start_with?("dependabot-alerts")
        cluster = ::Elastomer.router.cluster_for_index(name)
      end
      new(name, cluster)
    end
  end
end
