# typed: true
# frozen_string_literal: true

module Api::ProjectsV2::ItemContentPrefiller
  class << self # rubocop:disable Style/ClassMethodsDefinitions
    include GitHub::Tracing

    extend ActiveSupport::Concern
    extend T::Helpers

    sig do
      params(
        items: T.any(MemexProjectItem, T::Array[MemexProjectItem]),
        current_user: T.nilable(User),
        available_records: T::Array[ActiveRecord::Relation]
      ).void
    end
    def prefill_associations(items, current_user: nil, available_records: [])
      GitHub.tracer.in_span("item_content_prefiller/prefill_associations", kind: :internal) do
        items_array = Array.wrap(items)
        return if items_array.empty?

        GitHub::PrefillAssociations.prefill_associations( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          items_array,
          [
            { content: [:repository, :creator, { memex_project_item: [:creator, :memex_project] }] },
            { memex_project: { owner: :business_membership } },
            :creator,
            { repository: { owner: :trade_controls_restriction } },
            :issue,
          ],
          available_records:
        )

        # Group items by content type for batch processing
        pull_requests = []
        repositories = []
        issues = []
        agent_tasks = []

        items_array.each do |item|
          content = item.content
          repositories << item.repository
          issues << item.issue if item.issue

          case content
          when Issue
            issues << content
            repositories << content.repository
          when PullRequest
            pull_requests << content
            repositories << content.repository
          when DraftIssue
            # Do Nothing
          when MemexAgentTask
            agent_tasks << content
            repositories << content.repository
          end
        end

        # Prefill memex_project_items on agent tasks separately to avoid
        # triggering N+1 on Issue/PullRequest which also have this association.
        unless agent_tasks.empty?
          GitHub::PrefillAssociations.prefill_associations(
            agent_tasks,
            [{ memex_project_items: [:creator, :memex_project] }]
          )
        end

        pull_requests.compact!
        pull_requests.uniq!(&:object_id)

        repositories.compact!
        repositories.uniq!(&:object_id)

        issues.compact!
        issues.uniq!(&:object_id)

        available_records.concat([issues, repositories, pull_requests, current_user].flatten)
        available_records.compact!

        # Batch prefill repositories
        unless repositories.empty?
          # Prefill business_membership on org owners to avoid N+1 queries
          # during author_association checks and team visibility checks
          orgs = repositories.map(&:owner).grep(Organization).uniq
          GitHub::PrefillAssociations.prefill_batch_method(orgs, :teams)
          teams = orgs.flat_map(&:teams).uniq

          GitHub::PrefillAssociations.prefill_batch_method(teams, :parent_team)
          GitHub::PrefillAssociations.prefill_batch_method(repositories, :most_capable_user_role_for_actor, current_user) if current_user

          Configurable.preload_configuration(repositories)
          Repository.prefill_associations(repositories, internal: true)
          Repository.preload_repository_permissions(repositories:, users: Array.wrap(current_user).compact)
        end

        # Batch prefill issues
        unless issues.empty?
          IssuePrefiller.optimized_prefill(issues, current_user:, available_records:, exclude_prefills: [:closed_by]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          Reaction::Summary.prefill(issues)
        end

        # Batch prefill pull requests
        unless pull_requests.empty?
          # Group pull requests by repository for more efficient prefilling
          pull_requests_by_repo = pull_requests.group_by(&:repository)
          pull_requests_by_repo.each do |repository, repo_pull_requests|
            PullRequest.prefill_rest_api_list_repo_pulls(repo_pull_requests, current_user, mirror: true, repository:, users: Array.wrap(current_user), issues:)
          end

          # Prefill parent teams for PR team reviewers to avoid N+1 queries
          # during requested_teams serialization
          include_business_teams = FeatureFlag.vexi.enabled?(:business_team_memex_reviewers, default: false)
          pr_team_reviewers = pull_requests.flat_map do |p|
            matching_review_requests = p.review_requests_pending.select do |rr|
              rr.reviewer_type == "Team" || (include_business_teams && rr.reviewer_type == "BusinessTeam")
            end
            matching_review_requests.map(&:reviewer)
          end
          pr_team_reviewers.compact!
          unless pr_team_reviewers.empty?
            GitHub::PrefillAssociations.prefill_batch_method(pr_team_reviewers, :parent_team)

            # Batch all team visibility checks so Platform Loaders can batch
            # the underlying abilities queries into fewer round-trips
            if current_user
              all_pr_teams = (pr_team_reviewers + pr_team_reviewers.map(&:parent_team).compact).uniq
              visibility_promises = all_pr_teams.map { |team| team.async_visible_to?(current_user) }
              Promise.all(visibility_promises).sync
            end
          end
        end
      end
    end
  end
end
