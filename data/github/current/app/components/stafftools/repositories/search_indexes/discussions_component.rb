# typed: true
# frozen_string_literal: true

module Stafftools
  module Repositories
    module SearchIndexes
      class DiscussionsComponent < ApplicationComponent
        DOCUMENT_TYPE = "discussion"

        def initialize(repository:)
          @repository = repository
        end

        private

        attr_reader :repository

        delegate :discussions_active?, :discussions, to: :repository

        memoize def result
          index.search(query, type: DOCUMENT_TYPE, routing: repository.id)
        end

        def document_count
          Elastomer::UpgradeShims.get_total_hits(result["hits"])
        end

        def search_entry
          if document_count > 0
            result["hits"]["hits"].first["_source"]
          end
        end

        def search_entry?
          !search_entry.nil?
        end

        def index
          Elastomer::Indexes::Discussions.new
        end

        def query
          {
            query: {
              constant_score: {
                filter: {
                  term: {
                    repository_id: repository.id,
                  },
                },
              },
            },
            size: 1,
          }
        end

        def purge?
          !searchable? && search_entry?
        end

        def purge_reason
          if repository.spammy?
            "The repository owner has been flagged as spammy."
          elsif !discussions_active?
            "Discussions have been disabled for this repository."
          end
        end

        def searchable?
          !repository.spammy? && discussions_active?
        end

        def reindex?
          return false unless searchable?
          return true unless public_match?
          return true unless count_match?

          false
        end

        def reindex_reason
          if !public_match?
            "The repository's visibility has changed"
          elsif !count_match?
            "The discussion count differs from the database."
          end
        end

        def public_match?
          return true unless search_entry?

          repository.public == search_entry["public"]
        end

        def count_match?
          discussions.not_spammy.count == document_count
        end

        def purge_before_reindex?
          search_entry? && !public_match?
        end
      end
    end
  end
end
