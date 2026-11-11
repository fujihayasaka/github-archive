# typed: true
# frozen_string_literal: true

# Public: A preloader for the user's timeline contributions,
# with the goal of preventing N+1 queries when rendering the profile timeline.
# This logic is coupled to the implementation of the timeline. As the timeline evolves,
# so should this logic in order to preload necessary data and avoid preloading unnecessary
# data.
#
# Examples
#
#   # Build the timeline collector, then pass it to be preloaded
#   Profiles::User::TimelineContributionPreloader.preload(collector: collector)
#   # Now use collector methods to render the timeline
module Profiles
  module User
    class TimelineContributionPreloader
      METRIC = "profiles.user.timeline_contribution_preloader.preload.time"

      def initialize(collector:, contribs_per_repo_limit:, repos_per_rollup_limit:)
        @collector = collector
        @contribs_per_repo_limit = contribs_per_repo_limit
        @repos_per_rollup_limit = repos_per_rollup_limit
      end

      # Public: Preload associations on records loaded by the collector
      #
      # collector - the Contribution::Collector that will be used as a data source
      #             to render the user profile timeline.
      def self.preload(
        collector:,
        contribs_per_repo_limit: ProfilesController::CONTRIBS_PER_REPO_LIMIT,
        repos_per_rollup_limit: ProfilesController::REPOS_PER_ROLLUP_LIMIT
      )
        new(
          collector: collector,
          contribs_per_repo_limit: contribs_per_repo_limit,
          repos_per_rollup_limit: repos_per_rollup_limit
        ).preload!
      end

      def preload!
        return if user.large_bot_account?

        preload_associations_on_pull_requests
        preload_associations_on_pr_reviews
        preload_associations_on_created_repos
      end

      private

      attr_reader :collector, :contribs_per_repo_limit, :repos_per_rollup_limit
      delegate :user, to: :collector

      # Private: Preload data for created repositories that will be rendered in the timeline
      def preload_associations_on_created_repos
        measure("repositories") do
          GitHub::PrefillAssociations.prefill_associations(repos_to_render, [:mirror])
        end
      end

      # Private: Preload data for pull requests that will be rendered in the timeline
      def preload_associations_on_pull_requests
        # - Need issue for state methods like `pull_request.open?`
        # - Need issue repository for async_path_uri called for hovercard attributes
        measure("pull_requests") do
          GitHub::PrefillAssociations.prefill_associations(prs_to_render, { issue: :repository })
        end
      end

      # Private: Preload data for PR reviews that will be rendered in the timeline
      def preload_associations_on_pr_reviews
        measure("pull_request_reviews") do
          GitHub::PrefillAssociations.prefill_associations(pr_reviews_to_render, { pull_request: { issue: :repository } }) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end
      end

      # Private: Return all pull requests that will be rendered in the timeline
      def prs_to_render
        pr_contribs_by_repo = collector.pull_request_contributions_by_repository(exclude_first: true, exclude_popular: true)
        pr_contribs_by_repo.first(repos_per_rollup_limit).flat_map do |cbr|
          cbr.contributions.first(contribs_per_repo_limit).flat_map(&:pull_request)
        end
      end

      def pr_reviews_to_render
        review_contribs_by_repo = collector.pull_request_review_contributions_by_repository
        review_contribs_by_repo.first(repos_per_rollup_limit).flat_map do |cbr|
          cbr.contributions.first(contribs_per_repo_limit).flat_map(&:pull_request_review)
        end
      end

      def repos_to_render
        repo_contribs = collector.repository_contributions(exclude_first: true)
        repo_contribs.first(repos_per_rollup_limit).map(&:repository)
      end

      def measure(contribution_type)
        GitHub.dogstats.distribution_time(METRIC, tags: ["contribution_type:#{contribution_type}"]) do
          yield
        end
      end
    end
  end
end
