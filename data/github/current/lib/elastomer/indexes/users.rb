# typed: true
# frozen_string_literal: true

module Elastomer::Indexes

  # The Users index contains documents for users (and organizations).
  # These documents are searchable within this index.
  #
  class Users < ::Elastomer::Index

    # Defines the mappings for the 'user' document type.
    #
    # Returns the Hash containing the document type mappings.
    #
    def self.mappings_hook
      {
        user: {
          _all: { enabled: false },
          properties: {
            login: {
              type: "text",
              fields: {
                ngram: { type: "text", analyzer: "lowercase_ngram", search_analyzer: "lowercase" }
              },
              analyzer: "lowercase"
            },
            email: {
              type: "text",
              fields: {
                plain: { type: "text", analyzer: "email_loose", search_analyzer: "lowercase" }
              },
              analyzer: "email_strict",
              search_analyzer: "lowercase"
            },
            all_emails: { type: "text", analyzer: "lowercase" },
            user_id: { type: "integer" },
            followers: { type: "integer" },
            repos: { type: "integer" },
            name: { type: "text", analyzer: "name" },
            location: { type: "text" },
            language: { type: "keyword" },
            language_id: { type: "integer", doc_values: true },
            organization: { type: "boolean" },
            created_at: { type: "date" },
            updated_at: { type: "date" },
            rank: { type: "double" },
            profile_bio: { type: "text", analyzer: "texty" },
            all_org_ids: { type: "integer" },
            public_org_ids: { type: "integer" },
            business_id: { type: "keyword" },
            suspended_at: { type: "date" },
            sponsorable: { type: "boolean" }
          }
        }
      }
    end

    # Settings for a Users search index.
    #
    # Returns the Hash containing the settings for this index.
    #
    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_users,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          "queries.cache.enabled": true,
        },
        analysis: {
          analyzer: {
            name: {
              tokenizer: "standard",
              filter: %w[camelcase_words lowercase p_asciifolding],
            },
            email_strict: {
              tokenizer: "email",
              filter: %w[lowercase email_words],
            },
            email_loose: {
              tokenizer: "uax_url_email",
              filter: %w[lowercase],
            },
            lowercase: {
              tokenizer: "whitespace",
              filter: %w[lowercase],
            },
            lowercase_ngram: {
              tokenizer: "whitespace",
              filter: %w[lowercase ngram_text],
            },
          },
          tokenizer: {
            email: {
              type: "pattern",
              pattern: %q/(\S+)@\S+/,
              group: 1,
            },
          },
          filter: {
            remove_domain: {
              type: "pattern_replace",
              pattern: '(\S+)@\S+',
              replacement: "$1",
            },
            email_words: {
              type: "word_delimiter",
              generate_word_parts:     true,   # If true causes parts of words to be generated: “PowerShot” => “Power” “Shot”. Defaults to true.
              generate_number_parts:   true,   # If true causes number subwords to be generated: “500-42” => “500” “42”. Defaults to true.
              catenate_words:          false,  # If true causes maximum runs of word parts to be catenated: “wi-fi” => “wifi”. Defaults to false.
              catenate_numbers:        false,  # If true causes maximum runs of number parts to be catenated: “500-42” => “50042”. Defaults to false.
              catenate_all:            false,  # If true causes all subword parts to be catenated: “wi-fi-4000” => “wifi4000”. Defaults to false.
              split_on_case_change:    false,  # If true causes “PowerShot” to be two tokens; (“Power-Shot” remains two parts regards). Defaults to true.
              preserve_original:       true,   # If true includes original words in subwords: “500-42” => “500” “42” “500-42”. Defaults to false.
              split_on_numerics:       false,  # If true causes “j2se” to be three tokens; “j” “2” “se”. Defaults to true.
              stem_english_possessive: false,   # If true causes trailing “’s” to be removed for each subword: “O’Neil’s” => “O”, “Neil”. Defaults to true.
            },
            camelcase_words: {
              type: "word_delimiter",
              generate_word_parts:     true,
              generate_number_parts:   true,
              catenate_words:          false,
              catenate_numbers:        false,
              catenate_all:            false,
              split_on_case_change:    true,
              preserve_original:       true,
              split_on_numerics:       true,
              stem_english_possessive: false,
            },
            ngram_text: {
              type: "edgeNGram",
              min_gram: 2,
              max_gram: 20,
            },
            p_asciifolding: {
              type: "asciifolding",
              preserve_original: true,
            },
          },
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      settings
    end

    # Purge the user from the search index.
    #
    # user - The User for whom all search records will be purged.
    #
    # Returns this search index.
    def purge_user(user)
      docs.delete type: "user", id: user.id
      self
    end

    # Restore the user to the search index.
    #
    # user - The User for whom all search records will be restored.
    #
    # Returns this search index.
    def restore_user(user)
      store Elastomer::Adapters::User.create(user)
      self
    end

  end  # Users
end  # Elastomer::Indexes
