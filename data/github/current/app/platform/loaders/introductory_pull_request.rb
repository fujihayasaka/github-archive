# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    # Batches Elasticsearch lookups for introductory pull requests across
    # multiple commits. Instead of issuing 1 ES query per commit (N+1),
    # this loader collects all commits within a GraphQL execution, groups
    # them by repository, and issues one batched ES query per repository,
    # then pre-seeds each commit with the result. When
    # introductory_pull_request_ids! later runs on each commit, it finds
    # the pre-seeded value and uses a science experiment to validate it
    # against the per-commit ES query.
    #
    # See: https://github.com/github/azure-dotcom-environment/issues/206
    class IntroductoryPullRequest < Platform::Loader
      # key: Commit object
      # value: :preseeded (the actual data is set on the commit object)
      def fetch(commits)
        by_repo = commits.group_by(&:repository)

        by_repo.each do |repo, repo_commits|
          repo_ids = [repo&.id.to_i, repo&.parent_id].compact

          index = Elastomer::Indexes::PullRequests.new
          result = index.search_merged_including_commits(repo_commits, repo_ids)

          repo_commits.each do |commit|
            hits = result[:hits_by_oid][commit.oid] || []
            commit.preseed_introductory_pull_request_hits(
              hits: hits.first(2),
              timed_out: result[:timed_out]
            )
          end
        end

        commits.each_with_object({}) do |commit, results|
          # Pre-seed commits that had no hits from the batched query
          unless commit.introductory_pull_request_hits_preseeded?
            commit.preseed_introductory_pull_request_hits(hits: [], timed_out: false)
          end
          results[commit] = :preseeded
        end
      end
    end
  end
end
