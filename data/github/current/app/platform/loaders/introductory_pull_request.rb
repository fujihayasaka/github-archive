# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    # Batches Elasticsearch lookups for introductory pull requests across
    # multiple commits. Collects all commits within a GraphQL execution,
    # groups them by repository, and issues one batched _msearch request
    # per repository (chunked to OID_BATCH_SIZE).
    #
    # See: https://github.com/github/azure-dotcom-environment/issues/206
    class IntroductoryPullRequest < Platform::Loader
      OID_BATCH_SIZE = 50

      # key: Commit object
      # value: { hits: Array<Hash>, timed_out: Boolean }
      def fetch(commits)
        results = T.let({}, T::Hash[T.untyped, T::Hash[Symbol, T.untyped]])

        commits.group_by(&:repository).each do |repo, repo_commits|
          repo_ids = [repo&.id.to_i, repo&.parent_id].compact
          index = Elastomer::Indexes::PullRequests.new

          combined_hits = {}
          any_timed_out = T.let(false, T::Boolean)

          repo_commits.each_slice(OID_BATCH_SIZE) do |batch|
            result = index.search_merged_including_commits(batch, repo_ids)
            combined_hits.merge!(result[:hits_by_oid])
            any_timed_out ||= result[:timed_out]
          end

          repo_commits.each do |commit|
            hits = (combined_hits[commit.oid] || []).first(2)
            results[commit] = { hits: hits, timed_out: any_timed_out }
          end
        end

        # Commits without a repository (e.g. fork commits whose repo was not grouped)
        # are absent from results; default them so callers always get the
        # expected { hits:, timed_out: } shape.
        commits.each do |commit|
          results[commit] ||= { hits: [], timed_out: false }
        end

        results
      end
    end
  end
end
