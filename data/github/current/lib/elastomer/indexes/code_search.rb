# typed: true
# frozen_string_literal: true

module Elastomer::Indexes

  # The CodeSearch index contains all the source code files from all the
  # repositories currently stored out on the file servers.
  #
  class CodeSearch < ::Elastomer::Index
    # Defines the mappings for the 'issue' document type and the 'milestone'
    # document type.
    #
    # Returns the Hash containing the document type mappings.
    #
    def self.mappings_hook
      {
        code: {
          _all: { enabled: false },
          _routing: { required: true },
          properties: {
            path: {
              type: "text",
              fields: {
                filter: { type: "text", analyzer: "path_hierarchy" }
              },
              analyzer: "path_split"
            },
            filename: { type: "text", analyzer: "filename" },
            extension: { type: "keyword", doc_values: true },
            file: { type: "text", analyzer: "code", search_analyzer: "code_search" },
            file_size: { type: "long" },
            repo_id: { type: "integer" },
            public: { type: "boolean" },
            language: { type: "keyword" },
            language_id: { type: "integer" },
            blob_sha: { type: "keyword" },
            commit_sha: { type: "keyword" },
            timestamp: { type: "date" },
            fork: { type: "boolean" },
            head: { type: "keyword" },
            pushed_at: { type: "date" },
            is_code_search_state_doc: { type: "boolean" }
          }
        }
      }
    end

    # Settings for a CodeSearch search index.
    #
    # Returns the Hash containing the settings for this index.
    #
    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_code_search,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          refresh_interval: "60s",
          "queries.cache.enabled": true,
        },
        analysis: {
          analyzer: {
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
            trigram: {
              type: "custom",
              tokenizer: "trigram",
              filter: %w[lowercase],
            },
          },
          tokenizer: {
            path_hierarchy: {
              type: "path_hierarchy",
              delimiter: "/",
            },
            path_split: {
              type: "pattern",
              pattern: "/",
            },
            lines: {
              type: "pattern",
              pattern: "[\n\r]",
            },
            trigram: {
              type: "nGram",
              min_gram: 3,
              max_gram: 3,
            },
          },
        },
      }

      ::Elastomer::Analyzers.configure_code settings
      settings
    end

    # Enable SHA1 document IDs for code blobs
    def self.metadata
      {
        has_code_search_state_docs: true,
        sha1_document_ids: true,
      }
    end

    # Does this code-search index use the new-style SHA1 document IDs for
    # indexing code documents.
    def sha1_document_ids?
      return @sha1_document_ids if defined? @sha1_document_ids
      @sha1_document_ids = !!get_metadata["sha1_document_ids"]
    end

    # Public: Use this method to determine if the source code for a repository
    # has been indexed and which commit has been indexed.
    #
    # repo_id - The Integer ID of the repository.
    #
    # Examples
    #
    #   code_search.indexed_head(20669)
    #   #=> ["e0c80d8b334e5bc12174e5b1eee105f86ffc51da", "master"]
    #
    # Returns the Array containing the 'head_ref' and the 'head' branch name;
    # nil is returned if the repository source code is not indexed.
    #
    def indexed_head(repo_id)
      repo = repository(repo_id)
      return if repo.nil?

      get_metadata["has_code_search_state_docs"] ? [repo["commit_sha"], repo["head"]] : [repo["head_ref"], repo["head"]]
    end

    # Public: Find the current indexed state of the given repository. If the
    # repository has it's source code indexed, then the repository information
    # is returned. Otherwise nil is returned if the repository has not yet
    # been indexed
    #
    # repo_id - The Integer ID of the repository.
    #
    # Returns the indexed repository Hash or nil if the repository is absent.
    #
    def repository(repo_id)
      if get_metadata["has_code_search_state_docs"]
        result = docs.get(type: "code", id: repo_id, routing: repo_id)
      else
        result = docs.get(type: "repository", id: repo_id, routing: repo_id)
      end
      result["_source"]
    end

    # Public: Remove from the search index all the source code for the given
    # repository.
    #
    # repo_id - The Integer ID of the repository.
    #
    # Returns the HTTP response body as a Hash.
    #
    def remove_code(repo_id)
      delete_by_query({ term: { repo_id: repo_id } }, { type: %w[code repository], routing: repo_id })
    end

    # Public: Returns the number of files that exist in the index for the
    # given repository.
    #
    # repo_id - The Integer ID of the repository.
    #
    # Returns the number of indexed files.
    #
    def file_count(repo_id)
      count_query({ query: { bool: { must: { term: { repo_id: repo_id } }, must_not: { term: { "is_code_search_state_doc": true } } } } }, { type: "code", routing: repo_id })
    end

    # Purge all source code where the user is the owner.
    #
    # user - The User for whom all search records will be purged.
    #
    # Returns this search index.
    def purge_user(user)
      user.repository_ids.each do |repo_id|
        begin
          remove_code repo_id
        rescue StandardError => boom # rubocop:todo Lint/GenericRescue
          Failbot.report(boom.with_redacting!, "gh.repo.id": repo_id)
        end
      end

      self
    end

    # Restore all source code where the user is the owner.
    #
    # user - The User for whom all search records will be restored.
    #
    # Returns this search index.
    def restore_user(user)
      user.repository_ids.each do |repo_id|
        begin
          store Elastomer::Adapters::Code.create(repo_id)
        rescue StandardError => boom # rubocop:todo Lint/GenericRescue
          Failbot.report(boom.with_redacting!, "gh.repo.id": repo_id)
        end
      end

      self
    end

  end  # CodeSearch
end  # Elastomer::Indexes
