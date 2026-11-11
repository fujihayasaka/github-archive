# typed: true
# frozen_string_literal: true

module Elastomer::Indexes
  class Enterprises < ::Elastomer::Index
    def self.mappings_hook
      {
        topic: {
          _all: { enabled: false },
          properties: {
            slug: { type: "text", analyzer: "texty" },
            name: { type: "text", analyzer: "texty" },
            created_at: { type: "date" },
            updated_at: { type: "date" }
          }
        }
      }
    end

    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_enterprises,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          "queries.cache.enabled": true,
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      settings
    end
  end
end
