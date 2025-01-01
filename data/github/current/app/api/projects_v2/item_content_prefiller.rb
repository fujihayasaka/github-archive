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
      items_array = Array.wrap(items)
      return if items_array.empty?

      GitHub::PrefillAssociations.prefill_associations(
        items_array,
        [
          { content: :repository },
          { memex_project: :owner }
        ],
        available_records: available_records
      )

      # Group items by content type for batch processing
      issues = []
      pull_requests = []
      repositories = []

      items_array.each do |item|
        content = item.content
        case content
        when Issue
          issues << content
          repositories << content.repository
        when PullRequest
          pull_requests << content
          repositories << content.repository
        when DraftIssue
          # Do Nothing
        end
      end

      # Batch prefill issues
      unless issues.empty?
        if FeatureFlag.vexi.enabled?(:updated_issue_prefillers, default: false)
          IssuePrefiller.optimized_prefill(issues, current_user: current_user, available_records:) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        else
          associations = [:labels, :assignees, { repository: :owner }, { user: :profile }, :sub_issue_list, :blocking, :blocked_by, :issue_dependency_list, :parent_issue_relation]

          GitHub::PrefillAssociations.prefill_associations(issues, associations, available_records:)
          IssuePrefiller.preload_author_associations(issues, current_user)
        end

        Reaction::Summary.prefill(issues)
      end

      # Batch prefill pull requests
      unless pull_requests.empty?
        users = current_user ? [current_user] : []

        # Group pull requests by repository for more efficient prefilling
        pull_requests_by_repo = pull_requests.group_by(&:repository)
        pull_requests_by_repo.each do |repository, repo_pull_requests|
          PullRequest.prefill_rest_api_list_repo_pulls(repo_pull_requests, current_user, mirror: true, repository:, users:, issues:)
        end
      end

      # Batch prefill repositories
      Repository.prefill_associations(repositories, internal: true) unless repositories.empty?
    end
  end
end
