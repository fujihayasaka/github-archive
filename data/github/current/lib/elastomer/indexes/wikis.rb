# typed: true
# frozen_string_literal: true

module Elastomer::Indexes
  # The Wiki index contains documents for wiki pages and wiki state.
  class Wikis < ::Elastomer::Index
    # Defines the mappings for the 'wiki' and 'page' document types
    #
    # Returns the Hash containing the document type mappings.
    #
    def self.mappings_hook
      {
        page: {
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
            path: {
              type: "text",
              fields: {
                filter: { type: "text", analyzer: "path_hierarchy" }
              },
              analyzer: "path_split"
            },
            filename: { type: "text", analyzer: "filename" },
            format: { type: "text" },
            body: { type: "text", analyzer: "texty" },
            repo_id: { type: "integer" },
            business_id: { type: "integer" },
            revision: { type: "keyword" },
            public: { type: "boolean" },
            updated_at: { type: "date" },
            is_wiki_state_doc: { type: "boolean" }
          }
        }
      }
    end

    # Settings for a Wikis search index.
    #
    # Returns the Hash containing the settings for this index.
    #
    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_wikis,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          "queries.cache.enabled": true,
        },
        analysis: {
          analyzer: {
            path_hierarchy: {
              tokenizer: "path_hierarchy",
              filter: "lowercase",
            },
            path_split: {
              type: "custom",
              tokenizer: "path_split",
              filter: "lowercase",
            },
            filename: {
              type: "custom",
              tokenizer: "keyword",
              filter: %w[filename lowercase],
            },
            index_ngram_text: {
              tokenizer: "standard",
              filter: %w[lowercase ngram_text],
            },
            search_ngram_text: {
              tokenizer: "standard",
              filter: "lowercase",
            },
          },
          tokenizer: {
            path_split: {
              type: "pattern",
              pattern: "/",
            },
          },
          filter: {
            ngram_text: {
              type: "edgeNGram",
              min_gram: 2,
              max_gram: 20,
              side: "front",
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
            p_asciifolding: {
              type: "asciifolding",
              preserve_original: true,
            },
            filename: {
              type: "word_delimiter",
              generate_word_parts:     true,
              generate_number_parts:   true,
              catenate_words:          false,
              catenate_numbers:        false,
              catenate_all:            false,
              split_on_case_change:    true,
              preserve_original:       true,
              split_on_numerics:       false,
              stem_english_possessive: false,
            },
          },
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      settings
    end

    def self.metadata
      {
        has_wiki_state_docs: true,
      }
    end

    # Public: Use this method to determine if the wiki for a Repository
    # has been indexed and which commit has been indexed.
    #
    # repository_id - The Integer ID of the Repository.
    #
    # Examples
    #
    #   wikis.indexed_head(20669)
    #   #=> "e0c80d8b334e5bc12174e5b1eee105f86ffc51da"
    #
    # Returns the head oid or nil if the wiki is not indexed.
    #
    def indexed_head(repository_id)
      repo = repository(repository_id)
      return if repo.nil?

      repo["revision"]
    end

    # Public: Find the current indexed state of the wiki for a Repository. If
    # the wiki is indexed, then the wiki information is returned. Otherwise nil
    # is returned if the wiki has not yet been indexed.
    #
    # repository_id - The Integer ID of the repository.
    #
    # Returns the indexed wiki Hash or nil if the wiki is absent.
    #
    def repository(repository_id)
      if get_metadata["has_wiki_state_docs"]
        result = docs.get(type: "page", id: repository_id, routing: repository_id)
      else
        result = docs.get(type: "wiki", id: repository_id, routing: repository_id)
      end
      result["_source"]
    end

    # Public: Remove from the search index all wiki content for the given
    # Repository ids.
    #
    # repo_ids - List of repository ids.
    #
    # Returns the HTTP response body as a Hash.
    #
    def remove_wikis(*repo_ids)
      delete_by_query({ query: { terms: { repo_id: repo_ids.flatten } } }, { type: %w[page wiki] })
    end
    alias_method :remove_wiki, :remove_wikis

    # Public: Returns the number of pages that exist in the index for the
    # given repository.
    #
    # repo_id - The Integer ID of the repository.
    #
    # Returns the number of indexed pages
    #
    def page_count(repo_id)
      count_query({ query: { bool: { must: { term: { repo_id: repo_id } }, must_not: { term: { "is_wiki_state_doc": true } } } } }, { type: "page", routing: repo_id })
    end

    # Purge all wikis where the user is the owner.
    #
    # user - The User for whom all search records will be purged.
    #
    # Returns this search index.
    def purge_user(user)
      user.repository_ids.each do |repo_id|
        begin
          remove_wiki repo_id
        rescue Elastomer::Error, ElastomerClient::Error => boom
          Failbot.report boom, "gh.repo.id": repo_id
        end
      end

      self
    end

    # Restore all wikis where the user is the owner.
    #
    # user - The User for whom all search records will be restored.
    #
    # Returns this search index.
    def restore_user(user)
      user.repository_ids.each do |repo_id|
        begin
          store Elastomer::Adapters::Wiki.create(repo_id)
        rescue Elastomer::Error, ElastomerClient::Error => boom
          Failbot.report boom, "gh.repo.id": repo_id
        end
      end

      self
    end
  end
end
