# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    module Search
      class ReleasesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

        attr_reader :repository
        attr_reader :search_entry
        attr_reader :document_count

        def initialize(**args)
          super(args)

          @search_entry = nil

          index = Elastomer::Indexes::Releases.new
          query = {
            query: { constant_score: {
              filter: { term: { repo_id: repository.id } },
            } },
            size: 1,
          }
          result = index.search(query, type: "release")

          @document_count = Elastomer::UpgradeShims.get_total_hits(result["hits"])
          @search_entry = result["hits"]["hits"].first["_source"] if document_count > 0
        end

        def searchable?
          !repository.spammy?
        end

        def reindex?
          return false unless searchable?
          return true unless count_match?
          false
        end

        def reindex_reason
          return "The release count differs from the database." unless count_match?
          nil
        end

        def purge?
          !searchable? && search_entry?
        end

        def purge_reason
          return "The repository owner has been flagged as spammy." if repository.spammy?
          nil
        end

        def search_entry?
          !@search_entry.nil?
        end

        def count_match?
          repository.releases.count == document_count
        end
      end
    end
  end
end
