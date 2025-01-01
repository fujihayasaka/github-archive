# typed: true
# frozen_string_literal: true

module Elastomer::Indexes

  # The RegistryPackages index contains documents for registry packages.
  # These documents are searchable within this index.
  #
  class RegistryPackages < ::Elastomer::Index

    # Defines the mappings for the 'registry_package' document type.
    #
    # Returns the Hash containing the document type mappings.
    #
    def self.mappings_hook
      {
        registry_package: {
          _all: { enabled: false },
          _routing: { required: true },
          properties: {
            name: {
              type: "text",
              fields: {
                ngram: { type: "text", analyzer: "index_ngram_text", search_analyzer: "search_ngram_text" },
                raw: { type: "keyword" }
              },
              analyzer: "texty"
            },
            original_name: {
              type: "text",
              fields: {
                ngram: { type: "text", analyzer: "index_ngram_text", search_analyzer: "search_ngram_text" },
                raw: { type: "keyword" }
              },
              analyzer: "texty"
            },
            repo_id: { type: "integer" },
            business_id: { type: "integer" },
            public: { type: "boolean" },
            visibility: { type: "keyword" },
            summary: { type: "text", analyzer: "texty" },
            body: { type: "text", analyzer: "texty" },
            package_type: { type: "keyword" },
            package_subtype: { type: "keyword" },
            downloads: { type: "long" },
            versions: {
              type: "object",
              properties: {
                version: { type: "keyword" },
                latest: { type: "boolean" }
              }
            },
            applied_topics: { type: "text", analyzer: "lowercase" },
            created_at: { type: "date" },
            updated_at: { type: "date" },
            deleted_at: { type: "date" }
          }
        }
      }
    end

    # Settings for a Registry Package search index.
    #
    # Returns the Hash containing the settings for this index.
    #
    def self.settings_hook
      settings = {
        index: {
          number_of_shards:   GitHub.es_shard_count_for_registry_packages,
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
            lowercase: {
              tokenizer: "whitespace",
              filter: "lowercase",
            },
          },
          filter: {
            ngram_text: {
              type:     "edgeNGram",
              min_gram: 1,
              max_gram: 255,
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
      [::Elastomer.env.logical_index_name(self), ::Elastomer.env.index_name("packages")]
    end
  end
end
