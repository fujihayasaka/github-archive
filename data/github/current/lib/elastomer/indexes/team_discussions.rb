# typed: true
# frozen_string_literal: true

module Elastomer::Indexes
  # The TeamDiscussions index contains documents for team discussions. These documents are
  # searchable within this index.
  class TeamDiscussions < ::Elastomer::Index
    # Defines the mappings for the 'team_discussion' document type.
    #
    # Returns the Hash containing the document type mappings.
    def self.mappings_hook
      {
        team_discussion: {
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
            team_id: { type: "integer" },
            organization_id: { type: "integer" },
            pinned: { type: "boolean" },
            public: { type: "boolean" },
            num_replies: { type: "integer" },
            num_reactions: { type: "integer" },
            created_at: { type: "date" },
            updated_at: { type: "date" },
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
            },
            replies: {
              type: "object",
              properties: {
                discussion_post_reply_id: { type: "integer" },
                body: { type: "text", analyzer: "texty" },
                user_id: { type: "integer" },
                created_at: { type: "date" },
                updated_at: { type: "date" },
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
        }
      }
    end

    # Settings for a TeamDiscussions search index.
    #
    # Returns the Hash containing the settings for this index.
    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_team_discussions,
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
            },
          },
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      settings
    end
  end
end
