# typed: true
# frozen_string_literal: true

module Elastomer::Indexes

  # The Repos index contains documents for repositories. These documents are
  # searchable within this index.
  #
  class Repos < ::Elastomer::Index

    # Defines the mappings for the 'repository' document type.
    #
    # Returns the Hash containing the document type mappings.
    #
    def self.mappings_hook
      {
        repository: {
          _all: { enabled: false },
          properties: {
            name: {
              type: "text",
              fields: {
                camel: { type: "text", analyzer: "camelcase", search_analyzer: "search_camel" },
                ngram: { type: "text", analyzer: "camelcase_ngram", search_analyzer: "search_camel" }
              },
              analyzer: "lowercase"
            },
            name_sort: { type: "keyword" },
            name_with_owner: { type: "text", analyzer: "nwo" },
            description: { type: "text", analyzer: "texty" },
            readme: { type: "text", analyzer: "texty" },
            size: { type: "integer" },
            forks: { type: "integer" },
            fork: { type: "boolean" },
            template: { type: "boolean" },
            followers: { type: "integer" },
            owner_id: { type: "integer" },
            language: { type: "keyword" },
            language_id: { type: "integer", doc_values: true },
            pushed_at: { type: "date" },
            created_at: { type: "date" },
            updated_at: { type: "date" },
            public: { type: "boolean" },
            repo_id: { type: "integer" },
            business_id: { type: "integer" },
            visibility: { type: "keyword" },
            network_id: { type: "integer" },
            license_id: { type: "integer" },
            rank: { type: "double" },
            mirror: { type: "boolean" },
            archived: { type: "boolean" },
            sponsorable: { type: "boolean" },
            num_topics: { type: "integer" },
            has_funding_file: { type: "boolean" },
            help_wanted_issues_count: { type: "integer" },
            good_first_issue_issues_count: { type: "integer" },
            applied_topics: { type: "text", analyzer: "lowercase" },

            # Repository topics were previously known as hashtags. This field name
            # is a holdover from that.
            ranked_hashtags: {
              type: "nested",
              properties: {
                applied: { type: "text", analyzer: "lowercase" },
                rank: { type: "double" }
              }
            },
            # Properties is an array of serialized pairs, each one with the shape "key:value"
            custom_property_values: {
              type: "text",
              fields: {
                keyword: { type: "keyword", "ignore_above": 256 },
              },
            },
          }
        }
      }
    end

    # Settings for a Repos search index.
    #
    # Returns the Hash containing the settings for this index.
    #
    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_repos,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          "queries.cache.enabled": true,
        },
        analysis: {
          analyzer: {
            lowercase: {
              tokenizer: "whitespace",
              filter: %w[lowercase],
            },
            camelcase: {
              tokenizer: "repo_name",
              filter: %w[camelcase_words lowercase],
            },
            camelcase_ngram: {
              tokenizer: "repo_name",
              filter: %w[camelcase_words lowercase ngram_text],
            },
            search_camel: {
              tokenizer: "repo_name",
              filter: %w[lowercase],
            },
            nwo: {
              tokenizer: "repo_name",
              filter: %w[lowercase],
            },
          },
          tokenizer: {
            # This tokenizer is closely tied to the `EntityName.normalize`
            # method. We exepct any inputs to this tokenizer to have been
            # processed by the normalizer method. So the only characters we need
            # to separate on are those listed below.
            repo_name: {
              type: "pattern",
              pattern: '[._\-\s/]',
            },
          },
          filter: {
            camelcase_words: {
              type: "word_delimiter",
              generate_word_parts:     true,   # If true causes parts of words to be generated: “PowerShot” => “Power” “Shot”. Defaults to true.
              generate_number_parts:   true,   # If true causes number subwords to be generated: “500-42” => “500” “42”. Defaults to true.
              catenate_words:          false,  # If true causes maximum runs of word parts to be catenated: “wi-fi” => “wifi”. Defaults to false.
              catenate_numbers:        false,  # If true causes maximum runs of number parts to be catenated: “500-42” => “50042”. Defaults to false.
              catenate_all:            false,  # If true causes all subword parts to be catenated: “wi-fi-4000” => “wifi4000”. Defaults to false.
              split_on_case_change:    true,   # If true causes “PowerShot” to be two tokens; (“Power-Shot” remains two parts regards). Defaults to true.
              preserve_original:       true,   # If true includes original words in subwords: “500-42” => “500” “42” “500-42”. Defaults to false.
              split_on_numerics:       true,   # If true causes “j2se” to be three tokens; “j” “2” “se”. Defaults to true.
              stem_english_possessive: false,   # If true causes trailing “’s” to be removed for each subword: “O’Neil’s” => “O”, “Neil”. Defaults to true.
            },
            ngram_text: {
              type: "edgeNGram",
              min_gram: 1,
              max_gram: 20,
            },
          },
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      settings
    end

    # Purge all repositories where the user is the owner.
    #
    # user - The User for whom all search records will be purged.
    #
    # Returns this search index.
    def purge_user(user)
      delete_by_query({ term: { owner_id: user.id } }, type: "repository")
      self
    end

    # Restore all repositories where the user is the owner.
    #
    # user - The User for whom all search records will be restored.
    #
    # Returns this search index.
    def restore_user(user)
      user.repository_ids.each do |repo_id|
        begin
          store Elastomer::Adapters::Repository.create(repo_id)
        rescue StandardError => boom # rubocop:todo Lint/RescueException
          Failbot.report(boom.with_redacting!, "gh.repo.id": repo_id)
        end
      end

      self
    end

  end  # Repos
end  # Elastomer::Indexes
