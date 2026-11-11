# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    module Search
      class IssuesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

        attr_reader :repository
        attr_reader :search_entry
        attr_reader :document_count

        def initialize(*args)
          super(*T.unsafe(args))
          @search_entry = nil

          index = Elastomer::Indexes::Issues.new
          query = {
            query: { constant_score: {
              filter: { term: { repo_id: repository.id } },
            } },
            size: 1,
          }
          result = index.search(query, type: "issue", routing: repository.id)

          @document_count = Elastomer::UpgradeShims.get_total_hits(result["hits"])
          @search_entry = result["hits"]["hits"].first["_source"] if document_count > 0
        end

        def searchable?
          !repository.spammy? && repository.has_issues?
        end

        def reindex?
          return false unless searchable?
          return true  unless public_match?
          return true  unless count_match?
          false
        end

        def reindex_reason
          return "The public flag has been udpated."          unless public_match?
          return "The issue count differs from the database." unless count_match?
          nil
        end

        def purge?
          !searchable? && search_entry?
        end

        def purge_reason
          return "The repository owner has been flagged as spammy." if repository.spammy?
          return "Issues have been disabled for this repository."   if !repository.has_issues?
          nil
        end

        def search_entry?
          !@search_entry.nil?
        end

        def public_match?
          return true unless search_entry?
          repository.public == search_entry["public"]
        end

        # FIXME: this defaults to true. It is difficult to get a count of
        # valid issues from the database. The search index excludes issues
        # that are authored by spammy users.
        def count_match?
          # repository.issues.where(pull_request_id: nil).count == document_count
          true
        end

        def purge_before_reindex?
          search_entry? && !public_match?
        end
      end
    end
  end
end
