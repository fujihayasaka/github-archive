# typed: true
# frozen_string_literal: true

module Elastomer::Indexes

  # The Showcase index contains documents for showcase collections.
  #
  class Showcases < ::Elastomer::Index

    # Defines the mappings for the 'showcase_collection' document type.
    #
    # Returns the Hash containing the document type mappings.
    #
    def self.mappings_hook
      {
        showcase_collection: {
          _all: { enabled: false },
          properties: {
            name: { type: "text", analyzer: "texty" },
            slug: { type: "keyword" },
            body: { type: "text", analyzer: "texty" },
            published: { type: "boolean" },
            created_at: { type: "date" },
            updated_at: { type: "date" },
            items: {
              type: "object",
              properties: {
                item_id: { type: "integer" },
                item_name: { type: "text", analyzer: "texty" },
                item_description: { type: "text", analyzer: "texty" },
                body: { type: "text", analyzer: "texty" },
                created_at: { type: "date" },
                updated_at: { type: "date" }
              }
            }
          }
        }
      }
    end

    # Settings for a Showcase search index.
    #
    # Returns the Hash containing the settings for this index.
    #
    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_showcases,
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
