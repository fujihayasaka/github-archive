# typed: true
# frozen_string_literal: true

module Elastomer::Indexes

  # The Project Cards index contains documents for project cards.
  # These documents are searchable within this index.
  #
  class ProjectCards < ::Elastomer::Index

    # Defines the mappings for the 'project cards' document type.
    #
    # Returns the Hash containing the document type mappings.
    #
    def self.mappings_hook
      {
        project_card: {
          _all: { enabled: false },
          properties: {
            project_id: { type: "integer" },
            type: { type: "keyword" },
            title: {
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
            state: { type: "keyword" },
            author_id: { type: "integer" },
            labels: { type: "keyword" },
            assignee_ids: { type: "integer" },
            milestone_num: { type: "integer" },
            created_at: { type: "date" },
            updated_at: { type: "date" }
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
          number_of_shards: GitHub.es_shard_count_for_projects,
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
              filter:    %w[lowercase],
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
