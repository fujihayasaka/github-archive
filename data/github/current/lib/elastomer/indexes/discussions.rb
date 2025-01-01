# typed: true
# frozen_string_literal: true

module Elastomer::Indexes
  # The Discussions index contains documents for discussions. These documents are
  # searchable within this index.
  class Discussions < ::Elastomer::Index
    # Defines the mappings for the 'discussion' document type.
    #
    # Returns the Hash containing the document type mappings.
    def self.mappings_hook
      {
        discussion: {
          _all: { enabled: false },
          _routing: { required: true },
          properties: {
            title: {
              type: "text",
              fields: {
                ngram: { type: "text", analyzer: "index_ngram_text", search_analyzer: "search_ngram_text" }
              },
              analyzer: "texty"
            },
            body: { type: "text", analyzer: "texty" },
            user_id: { type: "integer" },
            answered_by_id: { type: "integer" },
            repository_id: { type: "integer" },
            public: { type: "boolean" },
            num_comments: { type: "integer" },
            interaction_score: { type: "integer" },
            num_interactions: { type: "integer" },
            total_upvotes: { type: "integer" },
            locked: { type: "boolean" },
            state: { type: "keyword" },
            state_reason: { type: "keyword" },
            answered: { type: "boolean" },
            participating_user_ids: { type: "integer" },
            number: { type: "integer" },
            created_at: { type: "date" },
            updated_at: { type: "date" },
            bumped_at: { type: "date" },
            closed_at: { type: "date" },
            comments: {
              type: "object",
              properties: {
                comment_id: { type: "integer" },
                body: { type: "text", analyzer: "texty" },
                user_id: { type: "integer" },
                created_at: { type: "date" },
                updated_at: { type: "date" }
              }
            },
            category_id: { type: "integer" },
            labels: { type: "keyword" },
            num_reactions: { type: "integer" },
            reactions: {
              type: "object",
              properties: {
                "+1": { type: "integer" },
                "-1": { type: "integer" },
                smile: { type: "integer" },
                thinking_face: { type: "integer" },
                heart: { type: "integer" },
                tada: { type: "integer" }
              }
            }
          }
        }
      }
    end

    # Settings for a Discussions search index.
    #
    # Returns the Hash containing the settings for this index.
    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_discussions,
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
              filter: %w[lowercase],
            },
          },
          filter: {
            ngram_text: {
              type: "edgeNGram",
              min_gram: 2,
              max_gram: 20,
              side: "front",
            },
          },
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      settings
    end
  end
end
