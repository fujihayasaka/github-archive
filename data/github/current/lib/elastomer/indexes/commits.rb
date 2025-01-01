# typed: true
# frozen_string_literal: true

module Elastomer::Indexes
  class Commits < ::Elastomer::Index
    def self.mappings_hook
      {
        commit: {
          _all: { enabled: false },
          _routing: { required: true },
          properties: {
            hash: { type: "keyword" },
            parent_hashes: { type: "keyword" },
            tree_hash: { type: "keyword" },
            is_merge: { type: "boolean" },
            author_id: { type: "integer" },
            author_name: { type: "text", analyzer: "name" },
            author_email: { type: "text", analyzer: "lowercase" },
            author_date: { type: "date" },
            committer_id: { type: "integer" },
            committer_name: { type: "text", analyzer: "name" },
            committer_email: { type: "text", analyzer: "lowercase" },
            committer_date: { type: "date" },
            message: { type: "text", analyzer: "texty" },
            public: { type: "boolean" },
            repo_id: { type: "integer" },
            head_branch: { type: "keyword" },
            pushed_at: { type: "date" },
            is_commit_state_doc: { type: "boolean" }
          }
        },
      }
    end

    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_commits,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          refresh_interval: "60s",
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
            path_hierarchy: {
              type: "custom",
              tokenizer: "path_hierarchy",
              filter: %w[lowercase],
            },
            path_split: {
              type: "custom",
              tokenizer: "path_split",
              filter: %w[lowercase],
            },
            lowercase: {
              tokenizer: "whitespace",
              filter: %w[lowercase],
            },
          },
          tokenizer: {
            email: {
              type: "pattern",
              pattern: %q/(\S+)@\S+/,
              group: 1,
            },
            path_hierarchy: {
              type: "path_hierarchy",
              delimiter: "/",
            },
            path_split: {
              type: "pattern",
              pattern: "/",
            },
          },
          filter: {
            camelcase_words: {
              type: "word_delimiter",
              generate_word_parts: true,
              generate_number_parts: true,
              catenate_words: false,
              catenate_numbers: false,
              catenate_all: false,
              split_on_case_change: true,
              preserve_original: true,
              split_on_numerics: true,
              stem_english_possessive: false,
            },
            email_words: {
              type: "word_delimiter",
              generate_word_parts: true,
              generate_number_parts: true,
              catenate_words: false,
              catenate_numbers: false,
              catenate_all: false,
              split_on_case_change: false,
              preserve_original: true,
              split_on_numerics: false,
              stem_english_possessive: false,
            },
            p_asciifolding: {
              type: "asciifolding",
              preserve_original: true,
            },
          },
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      ::Elastomer::Analyzers.configure_code settings
      settings
    end

    def self.metadata
      {
        has_commit_state_docs: true,
      }
    end

    # Public: Find the current indexed state of the given repository. If the
    # repository has its source code indexed, then the repository information
    # is returned. Otherwise nil is returned if the repository has not yet
    # been indexed
    #
    # repo_id - The Integer ID of the repository.
    #
    # Returns the indexed repository Hash or nil if the repository is absent.
    def repository(repo_id)
      if get_metadata["has_commit_state_docs"]
        result = docs.get({ type: "commit", id: repo_id, routing: repo_id })
      else
        result = docs.get({ type: "repository", id: repo_id, routing: repo_id })
      end
      result["_source"]
    end

    # Public: Returns the number of commits that exist in the index for the
    # given repository.
    #
    # repo_id - The Integer ID of the repository.
    #
    # Returns the number of indexed commits.
    def commit_count(repo_id)
      count_query({ query: { bool: { must: { term: { repo_id: repo_id } }, must_not: { term: { "is_commit_state_doc": true } } } } }, { type: "commit", routing: repo_id })
    end

    # Public: Get the hash of the latest commit that was indexed.
    #
    # repo_id - The Integer ID of the repository.
    #
    # Examples
    #
    #   commits.indexed_head_hash(20669)
    #   #=> ["e0c80d8b334e5bc12174e5b1eee105f86ffc51da", "master"]
    #
    # Returns the head hash or nil if the commits are not indexed.
    def indexed_head_hash(repo_id)
      repo = repository(repo_id)
      return if repo.nil?

      get_metadata["has_commit_state_docs"] ? repo["hash"] : repo["head_hash"]
    end

    # Public: Remove all the commits for the given repository from the search index.
    #
    # repo_id - The Integer ID of the repository.
    #
    # Returns the HTTP response body as a Hash.
    def remove_commits(repo_id)
      delete_by_query({ term: { repo_id: repo_id } }, { type: %w[commit repository], routing: repo_id })
    end

    # Purge all commits owned by a user.
    #
    # user - The User for whom all search records will be purged.
    #
    # Returns this search index.
    def purge_user(user)
      user.repository_ids.each do |repo_id|
        remove_commits(repo_id)
      end

      self
    end

    # Restore all commits owned by a user.
    #
    # user - The User for whom all search records will be restored.
    #
    # Returns this search index.
    def restore_user(user)
      user.repository_ids.each do |repo_id|
        store(Elastomer::Adapters::Commit.create(repo_id))
      end

      self
    end
  end
end
