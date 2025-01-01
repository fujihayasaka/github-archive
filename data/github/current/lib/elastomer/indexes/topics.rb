# typed: true
# frozen_string_literal: true

module Elastomer::Indexes
  # The Topics index contains documents for the `topics` table.
  #
  # These documents are searchable within this index.
  class Topics < ::Elastomer::Index
    # Defines the mappings for the 'topic' document type.
    #
    # Returns the Hash containing the document type mappings.
    def self.mappings_hook
      {
        topic: {
          _all: { enabled: false },
          properties: {
            name: {
              type: "text",
              fields: {
                ngram: { type: "text", analyzer: "index_ngram_text", search_analyzer: "search_ngram_text" }
              },
              analyzer: "lowercase"
            },
            display_name: { type: "text", analyzer: "texty" },
            short_description: { type: "text", analyzer: "texty" },
            description: { type: "text", analyzer: "texty" },
            created_by: { type: "text", analyzer: "texty" },
            released: { type: "keyword" },
            created_at: { type: "date" },
            updated_at: { type: "date" },
            featured: { type: "boolean" },
            curated: { type: "boolean" },
            repository_count: { type: "integer" },
            aliases: { type: "text", analyzer: "texty" },
            related: { type: "keyword" }
          }
        }
      }
    end

    # Settings for a MarketplaceListing search index.
    #
    # Returns the Hash containing the settings for this index.
    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_topics,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          "queries.cache.enabled": true,
        },
        analysis: {
          analyzer: {
            index_ngram_text: {
              tokenizer: "standard",
              filter: %w[lowercase ngram_text],
            },
            search_ngram_text: {
              tokenizer: "standard",
              filter: "lowercase",
            },
            lowercase: {
              tokenizer: "whitespace",
              filter: "lowercase",
            },
          },
          filter: {
            ngram_text: {
              type: "edgeNGram",
              min_gram: 2,
              max_gram: 20,
            },
          },
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      settings
    end
  end
end
