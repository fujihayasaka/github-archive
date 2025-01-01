# typed: true
# frozen_string_literal: true

module Elastomer::Indexes

  # The Projects index contains documents for projects.
  # These documents are searchable within this index.
  #
  class Projects < ::Elastomer::Index

    # Defines the mappings for the 'project' document type.
    #
    # Returns the Hash containing the document type mappings.
    #
    def self.mappings_hook
      {
        project: {
          _all: { enabled: false },
          properties: {
            name: {
              type: "text",
              fields: {
                ngram: { type: "text", analyzer: "index_ngram_text", search_analyzer: "search_ngram_text" },
                raw: { type: "keyword" }
              },
              analyzer: "texty"
            },
            body: { type: "text", analyzer: "texty" },
            creator_id: { type: "integer" },
            created_at: { type: "date" },
            updated_at: { type: "date" },
            closed_at: { type: "date" },
            org_id: { type: "integer" },
            repo_id: { type: "integer" },
            business_id: { type: "integer" },
            user_id: { type: "integer" },
            public: { type: "boolean" },
            number: { type: "integer" },
            project_type: { type: "keyword" },
            state: { type: "keyword" },
            linked_repository_id: { type: "integer" }
          }
        }
      }
    end

    # Settings for a Project search index.
    #
    # Returns the Hash containing the settings for this index.
    #
    def self.settings_hook
      settings = {
        index: {
          number_of_shards:   GitHub.es_shard_count_for_projects,
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
  end
end
