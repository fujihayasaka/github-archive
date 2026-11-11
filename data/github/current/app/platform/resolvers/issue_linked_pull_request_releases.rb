# typed: strict
# frozen_string_literal: true

module Platform
  module Resolvers
    # Resolves the earliest release for each linked (merged) pull request on an issue.
    # Returns at most one release per PR: stable preferred over pre-release,
    # earliest published_at first (i.e. the release that first shipped the PR).
    #
    # Data path:
    #   Issue → close_issue_references → merged PRs (via PullRequests::PullRequestAccessor)
    #     → Tags::Public.tags_containing_commit per SHA (within time budget)
    #     → Releases::Public.published_releases_by_tag
    #     → pick best release per PR
    #
    # Domain ownership:
    #   - PR query: packages/pull_requests (PullRequestAccessor.merged_by_ids)
    #   - Tag lookup: packages/repositories (Tags::Public.tags_containing_commit)
    #   - Release lookup: packages/releases (Releases::Public.published_releases_by_tag)
    #   - Orchestration + selection policy: this resolver (packages/issues)
    #
    # Performance: early-exits when no releases exist, 3 s monotonic-time budget,
    # max 500 tags/SHA with lazy pagination, batched release lookup,
    # OTel span + dogstats metrics.
    class IssueLinkedPullRequestReleases < Resolvers::Base
      type Connections.define(Objects::LinkedPullRequestRelease), null: true

      METRIC_PREFIX = "issue_linked_pr_releases"
      PR_ACCESSOR = ::PullRequests::PullRequestAccessor.new

      # Match the client's `first: 10` on closedByPullRequestsReferences.
      MAX_PRS_TO_CHECK = 10

      # Timeout (in seconds) for the entire git tag lookup phase.
      GIT_LOOKUP_TIMEOUT_SECONDS = 3

      # Max tags to collect per SHA; caps cost for repos with excessive tags.
      MAX_TAGS_PER_SHA = 500

      class LinkedPullRequestRelease < T::Struct
        const :pull_request, ::PullRequest
        const :release, Releases::IRelease
      end

      sig { params(arguments: T.untyped).returns(Promise[ArrayWrapper]) }
      def resolve(**arguments)
        issue = object
        return Promise.resolve(ArrayWrapper.new) unless issue.present?

        issue.async_repository.then do |repo|
          next ArrayWrapper.new unless repo

          unless repo.releases.published.exists?
            GitHub.dogstats.increment("#{METRIC_PREFIX}.no_releases")
            next ArrayWrapper.new
          end

          repo_nwo = repo.name_with_display_owner
          GitHub.dogstats.distribution_time("#{METRIC_PREFIX}.resolve.dist") do
            ArrayWrapper.new(resolve_for(issue, repo, repo_nwo: repo_nwo))
          end
        end
      end

      private

      sig { params(issue: Issue, repo: Repository, repo_nwo: String).returns(T::Array[LinkedPullRequestRelease]) }
      def resolve_for(issue, repo, repo_nwo:)
        # Issues domain: get linked PR IDs
        pr_ids = issue.close_issue_references
          .where.not(pull_request_id: nil)
          .limit(MAX_PRS_TO_CHECK * 2)
          .pluck(:pull_request_id)
        return [] if pr_ids.empty?

        # Pull Requests domain: load merged PRs
        merged_prs = PR_ACCESSOR.merged_by_ids(
          pull_request_ids: pr_ids, repository_id: repo.id, limit: MAX_PRS_TO_CHECK
        )
        return [] if merged_prs.empty?

        # Viewer authorization: filter out PRs the viewer may not see.
        # Mirrors the checks in ClosedByPullRequestsReferences.
        cap_filter = context[:cap_filter]
        merged_prs = cap_filter.authorized_resources(merged_prs) if cap_filter
        viewer = context[:viewer]
        merged_prs = merged_prs.reject { |pr| (pr.spammy? || repo.spammy?) && !viewer&.site_admin? }
        return [] if merged_prs.empty?

        GitHub.dogstats.distribution("#{METRIC_PREFIX}.pr_count.dist", merged_prs.size)

        # Repositories domain: find tags containing each merge commit SHA
        merge_shas = merged_prs.map(&:merge_commit_sha)
        tags_by_commit = find_tags_per_commit(repo, merge_shas, repo_nwo: repo_nwo)

        all_tag_names = tags_by_commit.values.flat_map(&:to_a).uniq
        return [] if all_tag_names.empty?

        # Releases domain: look up releases by tag
        releases_by_tag = GitHub.dogstats.distribution_time("#{METRIC_PREFIX}.release_query.dist") do
          Releases::Public.published_releases_by_tag(repo.id, all_tag_names)
        end

        # Selection policy (caller-specific): pair each PR with its earliest release
        results = merged_prs.filter_map do |pr|
          pr_tags = tags_by_commit[pr.merge_commit_sha]
          next if pr_tags.nil? || pr_tags.empty?

          earliest_release = pick_earliest_release(pr_tags, releases_by_tag)
          next unless earliest_release

          LinkedPullRequestRelease.new(pull_request: pr, release: earliest_release)
        end

        GitHub.dogstats.increment("#{METRIC_PREFIX}.empty_result") if results.empty?
        results
      end

      # Orchestrates Tags::Public.tags_containing_commit per SHA within a
      # monotonic time budget. Returns partial results if deadline is exceeded.
      sig { params(repo: Repository, shas: T::Array[String], repo_nwo: String).returns(T::Hash[String, T::Set[String]]) }
      def find_tags_per_commit(repo, shas, repo_nwo:)
        tags_by_commit = T.let({}, T::Hash[String, T::Set[String]])
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + GIT_LOOKUP_TIMEOUT_SECONDS

        GitHub.tracer.in_span("#{METRIC_PREFIX}.find_tags", kind: :internal, attributes: { "pr_count" => shas.size, "repo_nwo" => repo_nwo }) do
          shas.each do |sha|
            if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
              GitHub.dogstats.increment("#{METRIC_PREFIX}.timeout", tags: ["repo_nwo:#{repo_nwo}"])
              break
            end
            tags_by_commit[sha] = Tags::Public.tags_containing_commit(repository: repo, sha: sha, limit: MAX_TAGS_PER_SHA)
            tags = T.must(tags_by_commit[sha])

            if tags.size >= MAX_TAGS_PER_SHA
              GitHub.dogstats.increment("#{METRIC_PREFIX}.tag_cap_hit")
            end
          end
        end

        total_tags = tags_by_commit.values.sum(&:size)
        GitHub.dogstats.distribution("#{METRIC_PREFIX}.tags_found.dist", total_tags)
        tags_by_commit
      end

      # Picks the earliest stable release that contains the PR (the release
      # that first shipped it); falls back to earliest pre-release.
      # This is caller-specific selection policy, not a releases-domain concern.
      sig { params(pr_tags: T::Set[String], releases_by_tag: T::Hash[String, Releases::IRelease]).returns(T.nilable(Releases::IRelease)) }
      def pick_earliest_release(pr_tags, releases_by_tag)
        candidates = pr_tags.filter_map { |tag| releases_by_tag[tag] }
        return nil if candidates.empty?

        stable, prerelease = candidates.partition { |r| !r.prerelease? }
        earliest = ->(list) { list.min_by { |r| r.published_at || r.created_at || Float::INFINITY } }

        earliest.call(stable) || earliest.call(prerelease)
      end
    end
  end
end
