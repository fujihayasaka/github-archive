# typed: true
# frozen_string_literal: true

module Elastomer::Indexes
  # The Labels index contains documents for the `labels` table.
  #
  # These documents are searchable within this index.
  class Labels < ::Elastomer::Index
    # Defines the mappings for the 'label' document type.
    #
    # Returns the Hash containing the document type mappings.
    def self.mappings_hook
      {
        label: {
          _all: { enabled: false },
          _routing: { required: true },
          properties: {
            name: {
              type: "text",
              fields: {
                ngram: { type: "text", analyzer: "index_ngram_text", search_analyzer: "search_ngram_text" },
                trigram: { type: "text", analyzer: "trigram_text", search_analyzer: "trigram_text" }
              },
              analyzer: "label_name",
              search_analyzer: "label_name_search"
            },
            repo_id: { type: "integer" },
            description: { type: "text", analyzer: "texty" },
            created_at: { type: "date" },
            updated_at: { type: "date" }
          }
        }
      }
    end

    # Settings for a Labels search index.
    #
    # Returns the Hash containing the settings for this index.
    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_labels,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          "queries.cache.enabled": true,
        },
        analysis: {
          analyzer: {
            index_ngram_text: {
              tokenizer: "whitespace",
              filter: %w[lowercase ngram_text],
            },
            search_ngram_text: {
              tokenizer: "whitespace",
              filter: %w[lowercase ngram_text],
            },
            trigram_text: {
              "tokenizer": "whitespace",
              "filter": %w[lowercase trigram]
            },
            lowercase: {
              tokenizer: "whitespace",
              filter: %w[lowercase],
            },
            label_name: {
              tokenizer: "whitespace",
              filter: %w[lowercase asciifolding keyword_repeat kstem texty_unique_words texty_words],
            },
            label_name_search: {
              tokenizer: "whitespace",
              filter: %w[lowercase asciifolding],
            },
          },
          filter: {
            ngram_text: {
              type: "edgeNGram",
              min_gram: 2,
              max_gram: 20,
              side: "front",
            },
            trigram: {
              type: "ngram",
              min_gram: 3,
              max_gram: 3,
              token_chars: %w[letter digit punctuation symbol],
            },
          },
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      settings
    end
  end
end
