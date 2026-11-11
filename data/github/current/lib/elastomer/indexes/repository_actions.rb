# typed: true
# frozen_string_literal: true

module Elastomer::Indexes
  # The RepositoryActions index contains documents for Actions.
  #
  # These documents are searchable within this index.
  class RepositoryActions < ::Elastomer::Index
    # Defines the mappings for the 'repository_action' document type.
    #
    # Returns the Hash containing the document type mappings.
    def self.mappings_hook
      {
        repository_action: {
          _all: { enabled: false },
          properties: {
            search_type: { type: "keyword" },
            name: {
              type: "text",
              fields: {
                ngram: { type: "text", analyzer: "index_ngram_text", search_analyzer: "search_ngram_text" },
                raw: { type: "keyword" }
              },
              analyzer: "texty"
            },
            owner_name: {
              type: "text",
              fields: {
                ngram: { type: "text", analyzer: "index_ngram_text", search_analyzer: "search_ngram_text" },
                raw: { type: "keyword" }
              },
              analyzer: "texty"
            },
            owner_login: {
              type: "text",
              fields: {
                ngram: { type: "text", analyzer: "index_ngram_text", search_analyzer: "search_ngram_text" },
                raw: { type: "text", analyzer: "publisher_search" }
              },
              analyzer: "texty"
            }, #This field data is also displayed in UI view
            description: { type: "text", analyzer: "texty" },
            created_at: { type: "date" },
            updated_at: { type: "date" },
            featured: { type: "boolean" },
            is_verified_owner: { type: "boolean" }, #This field data is also displayed in UI view
            rank_multiplier: { type: "float" },
            state: { type: "keyword" },
            repository_id: { type: "keyword" },
            primary_category: { type: "keyword" },
            secondary_category: { type: "keyword" },
            categories: {
              type: "text",
              fields: {
                raw: { type: "keyword" }
              }
            },
            stars: { type: "integer" }, #This field data is also displayed in UI view
            dependents_count: { type: "integer" }, #This field data is also displayed in UI view
          }
        }
      }
    end

    # Settings for a RepositoryAction search index.
    #
    # Returns the Hash containing the settings for this index.
    def self.settings_hook
      settings = {
        index: {
          number_of_shards:   GitHub.es_shard_count_for_repository_actions,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          "queries.cache.enabled": true,
        },
        analysis: {
          analyzer: {
            index_ngram_text: {
              tokenizer: "standard",
              filter:    %w[lowercase ngram_text],
            },
            search_ngram_text: {
              tokenizer: "standard",
              filter:    "lowercase",
            },
          },
          filter: {
            ngram_text: {
              type:     "edgeNGram",
              min_gram: 1,
              max_gram: 20,
              side:     "front",
            },
          },
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      settings
    end

    # Returns the Array of valid aliases for this index type.
    def self.aliases
      [::Elastomer.env.logical_index_name(self), ::Elastomer.env.index_name("marketplace-search")]
    end
  end
end
