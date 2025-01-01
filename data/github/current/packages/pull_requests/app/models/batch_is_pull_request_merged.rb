# typed: true
# frozen_string_literal: true

# Use a batch mode RPC to answer the following question for many PRs recently
# impacted by a single push (i.e. the push was to a PR's base or head ref):
#
#   "Should this PR be marked as merged?"
#
module BatchIsPullRequestMerged
  extend T::Sig

  PrecomputedResultType = T.type_alias { T.any(T::Boolean, Class) }

  # Sentinel value to explicitly indicate that the work was not done.
  NotPrecomputed = T.must(Class.new)

  class Result
    # Stored as a 2-level hash:
    #   { base_oid: { head_oid: (true OR false OR NotComputed) } }
    def initialize(base_to_tip_to_merged)
      @base_to_tip_to_merged = base_to_tip_to_merged
    end

    def fetch(base_oid:, head_oid:)
      @base_to_tip_to_merged[base_oid][head_oid]
    end
  end

  module EmptyResult
    def self.fetch(*)
      NotPrecomputed
    end
  end

  # Compute the is_merged state of all PRs that need to be synchronized
  # because of the passed ref update.
  # ref_update - The Git::Ref::Update that triggered this work.
  # Returns Result or EmptyResult, in either case an object
  # that satisfies the interface `#fetch(String, String): Boolean`
  sig { params(ref_update: PullRequest::RefUpdate).returns(T.any(Result, T::class_of(EmptyResult))) }
  def self.call(ref_update:)
    unless ref_update.before_oid.present? && ref_update.after_oid.present?
      return EmptyResult
    end

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Find all PRs which the updated branch is involved in. Ignore PRs with missing commit or repo ids -- in such cases,
    # we cannot meaningfully precompute a merge status. The sync job fetching them will just default to NotPrecomputed.
    synchronizable_pulls = ref_update.synchronizable_pulls.filter { |pr| pr.base_oid && pr.head_oid && pr.head_repo_id }

    # Find incoming PRs -- PRs where changes are being merged into the updated ref
    unqualified_refname = ref_update.qualified_refname.delete_prefix("refs/heads/")
    prs_as_base = synchronizable_pulls.filter { |pr| pr.base_repo_id == ref_update.repository.id && pr.base_ref == unqualified_refname }
    total_pr_heads = 0

    # There's no performance benefit to "batching" a single PR, and the result might become stale and need to be recomputed.
    if prs_as_base.count >= 2
      # For any (base, tip) pair we didn't pre-compute, return NotPrecomputed
      base_to_tip_to_merged = Hash.new { |h, k| h[k] = Hash.new(NotPrecomputed) }

      # For each PR where this branch is the base, look to see if it already contains the head branch of the PR.
      pr_base_oid = T.must(prs_as_base.first).base_oid
      all_pr_head_oids = prs_as_base.map(&:head_oid).uniq

      total_pr_heads = all_pr_head_oids.size

      base_contains_head = ref_update.repository.spokes_api.ahead_behind_contains(base: pr_base_oid, tips: all_pr_head_oids)
        .to_h { |pr_head_oid| [pr_head_oid, true] }

      all_pr_head_oids.each do |pr_head_oid|
        base_to_tip_to_merged[pr_base_oid][pr_head_oid] = !!(base_contains_head[pr_head_oid])
      end
    end

    total_time = GitHub::Dogstats.duration(start_time)
    pull_count = synchronizable_pulls.size

    GitHub.dogstats.distribution("pull_request_batched_is_merged.timing", total_time)
    GitHub.dogstats.distribution("pull_request_batched_is_merged.pull_count", pull_count)
    GitHub.dogstats.distribution("pull_request_batched_is_merged.timing_per_pull", total_time.fdiv(pull_count))
    GitHub.dogstats.distribution("pull_request_batched_is_merged.incoming_pull_count", prs_as_base.size)
    GitHub.dogstats.distribution("pull_request_batched_is_merged.total_pr_heads", total_pr_heads)

    if base_to_tip_to_merged
      Result.new(base_to_tip_to_merged)
    else
      EmptyResult
    end
  end
end
