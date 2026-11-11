# typed: true
# frozen_string_literal: true

module Elastomer::Indexes

  # The Gists index contains documents for gists. These documents are
  # searchable within this index.
  class Gists < ::Elastomer::Index

    # Defines the mappings for the 'gist' type.
    #
    # Returns the Hash containing the document type mappings.
    def self.mappings_hook
      {
        gist: {
          _all: { enabled: false },
          properties: {
            gist_id: { type: "integer" },
            owner_id: { type: "integer" },
            forks: { type: "integer" },
            fork: { type: "boolean" },
            public: { type: "boolean" },
            stars: { type: "integer" },
            description: { type: "text", analyzer: "texty" },
            created_at: { type: "date" },
            updated_at: { type: "date" },
            head: { type: "keyword" },
            head_ref: { type: "keyword" },
            code: {
              type: "object",
              properties: {
                filename: { type: "text", analyzer: "filename" },
                extension: { type: "keyword" },
                file: { type: "text", analyzer: "code", search_analyzer: "code_search" },
                file_size: { type: "integer", doc_values: true },
                language: { type: "keyword" },
                language_id: { type: "integer", doc_values: true },
                timestamp: { type: "date" }
              }
            }
          }
        }
      }
    end

    # Settings for an Gists search index.
    #
    # Returns the Hash containing the settings for this index.
    def self.settings_hook
      settings = {
        index: {
          number_of_shards: GitHub.es_shard_count_for_gists,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          "queries.cache.enabled": true,
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      ::Elastomer::Analyzers.configure_code settings
      settings
    end

    # Public: Determine if the Gist already exists in the search index.
    #
    # Returns `true` if the gist has been indexed; `false` otherwise.
    def indexed?(gist_id)
      result = docs.get(type: "gist", id: gist_id, _source: false)
      result["found"]
    end

    # Public: Use this method to determine if the source code for a gist
    # has been indexed and which commit has been indexed.
    #
    # gist_id - The Integer ID of the gist.
    #
    # Examples
    #
    #   gists.indexed_head(20669)
    #   #=> "e0c80d8b334e5bc12174e5b1eee105f86ffc51da"
    #
    # Returns the last indexed commit SHA or nil if the gist source code
    # is not indexed.
    def indexed_head(gist_id)
      result = gist_repository(gist_id)
      result["head_ref"] unless result.nil?
    end

    # Public: Find the current indexed state of the source code for the given
    # gist. If the gist has it's source code indexed, then the repository
    # information is returned. Otherwise nil is returned if the gist has not
    # yet been indexed
    #
    # gist_id - The Integer ID of the gist.
    #
    # Returns the indexed gist Hash or nil if the gist is absent.
    def gist_repository(gist_id)
      params = {
        type: "gist",
        id: gist_id,
        _source: %w[head head_ref],
      }

      result = docs.get params
      result["_source"] unless result.nil?
    end

    # Purge all gists where the user is the owner.
    #
    # user - The User for whom all search records will be purged.
    #
    # Returns this search index.
    def purge_user(user)
      user.gist_ids.each do |gist_id|
        begin
          remove_gist gist_id
        rescue StandardError => boom # rubocop:todo Lint/RescueException
          Failbot.report(boom.with_redacting!, "gh.gist.id": gist_id)
        end
      end

      self
    end

    # Restore all gists where the user is the owner.
    #
    # user - The User for whom all search records will be restored.
    #
    # Returns this search index.
    def restore_user(user)
      user.gist_ids.each do |gist_id|
        begin
          store Elastomer::Adapters::Gist.create(gist_id)
        rescue StandardError => boom # rubocop:todo Lint/RescueException
          Failbot.report(boom.with_redacting!, "gh.gist.id": gist_id)
        end
      end

      self
    end

    # Public: Remove from the search index all the documents related to the
    # given gist.
    #
    # gist_id - The Integer ID of the gist.
    #
    # Returns the HTTP response body as a Hash.
    def remove_gist(gist_id)
      docs.delete(type: "gist", id: gist_id)
    end
  end
end
