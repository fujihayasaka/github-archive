# typed: true
# frozen_string_literal: true

module Elastomer::Indexes
  # The AzureModels index contains documents for Azure Models.
  #
  # These documents are searchable within this index.
  class AzureModels < ::Elastomer::Index
    # Defines the mappings for the 'azure_model' document type.
    #
    # Returns the Hash containing the document type mappings.
    def self.mappings_hook
      {
        azure_model: {
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
            state: { type: "keyword" },
            created_at: { type: "date" },
            updated_at: { type: "date" },
            popularity: { type: "float" },
            max_output_tokens: { type: "integer" },
            max_input_tokens: { type: "integer" },
            rate_limit_tier: { type: "keyword" },
            task: { type: "keyword" },
            publisher: { type: "keyword" },
            license: { type: "keyword" },
            notes: { type: "text", analyzer: "texty" },
            summary: { type: "text", analyzer: "texty" },
            description: { type: "text", analyzer: "texty" },
            license_description: { type: "text", analyzer: "texty" },
            categories: {
              type: "text",
              fields: {
                raw: { type: "keyword" }
              }
            },
            supported_input_modalities: { type: "text", fields: { raw: { type: "keyword" } } },
            supported_output_modalities: { type: "text", fields: { raw: { type: "keyword" } } },
            supported_languages: { type: "text", fields: { raw: { type: "keyword" } } },
          }
        }
      }
    end

    # Settings for a AzureModel search index.
    #
    # Returns the Hash containing the settings for this index.
    def self.settings_hook
      settings = {
        index: {
          number_of_shards:   GitHub.es_shard_count_for_repository_actions, # TODO: use models-specific value
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
