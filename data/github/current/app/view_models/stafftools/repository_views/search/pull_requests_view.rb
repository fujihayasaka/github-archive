# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    module Search
      class PullRequestsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

        attr_reader :repository
        attr_reader :search_entry
        attr_reader :document_count

        def initialize(*args)
          super
          @search_entry = nil

          index = Elastomer::Indexes::PullRequests.new
          query = {
            query: { constant_score: {
              filter: { term: { repo_id: repository.id } },
            } },
            size: 1,
          }
          result = index.search(query, type: "pull_request", routing: repository.id)

          @document_count = Elastomer::UpgradeShims.get_total_hits(result["hits"])
          @search_entry = result["hits"]["hits"].first["_source"] if document_count > 0
        end

        def searchable?
          !repository.spammy?
        end

        def reindex?
          return false unless searchable?
          return true  unless public_match?
          return true  unless count_match?
          false
        end

        def reindex_reason
          return "The public flag has been udpated."                 unless public_match?
          return "The pull request count differs from the database." unless count_match?
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

        def public_match?
          return true unless search_entry?
          repository.public == search_entry["public"]
        end

        # FIXME: this defaults to true. It is difficult to get a count of
        # valid pull requests from the database. The search index excludes PRs
        # that are authored by spammy users or that have missing base / head
        # refs, etc.
        def count_match?
          # repository.pull_requests.count == document_count
          true
        end

        def purge_before_reindex?
          search_entry? && !public_match?
        end

        def active_repair?
          repair_job = RepairPullRequestsIndexJob.new("pull-requests", repo_id: repository.id)
          repair_job.exists? && repair_job.enabled? && !repair_job.finished?
        end
      end
    end
  end
end
