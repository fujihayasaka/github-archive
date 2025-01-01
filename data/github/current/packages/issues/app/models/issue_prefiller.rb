# typed: true
# frozen_string_literal: true

module IssuePrefiller

  class << self
    PREFILLS_FOR_ISSUES = [:labels, :assignees, :assignments, :pull_request, :milestones, :close_issue_references, :closed_by, :sub_issue_list]
    BATCH_SIZE = 1000

    # Public: Preloads Issue#user, Issue#milestone, Issue#assignee, and Issue#labels.
    #
    # issues - An Array of Issues.
    #
    # Optional keyword args to configure what associations to load.
    #     repository: - Repository instance to preload on all issues.
    #
    # Returns nothing.
    def prefill(issues, repository: nil, only_prefill: PREFILLS_FOR_ISSUES, exclude_prefills: [], current_user: nil, tags: [])
      only_prefill = only_prefill.map(&:to_sym) - exclude_prefills.map(&:to_sym)

      associations_to_prefill = [{ user: :profile }, :repository]
      associations_to_prefill << T.unsafe([:labels, :assignees, :assignments, :sub_issue_list] & only_prefill)
      associations_to_prefill << { assignee: :profile } if only_prefill.include?(:assignees)
      associations_to_prefill << { milestone: [:created_by, :repository] } if only_prefill.include?(:milestones)
      associations_to_prefill << :pull_request if only_prefill.include?(:pull_request)

      GitHub::PrefillAssociations.prefill_associations(issues, associations_to_prefill, available_records: [repository])

      prefill_close_issue_reference_counts(issues, current_user) if only_prefill.include?(:close_issue_references)

      if (GitHub.flipper[:prefill_issue_closed_by].enabled? || current_user&.feature_enabled?(:prefill_issue_closed_by)) && only_prefill.include?(:closed_by)
        prefill_closed_by(issues)
      end
    end

    private

    def prefill_closed_by(issues)
      # Batch load the closed issue events
      events = Platform::Loaders::ClosedIssueEvents.load_all(
        issues.map(&:id),
        omit_event_detail: true,
        fields: [:actor_id, :issue_id],
        order: "DESC",
      ).sync

      # Batch fetch the actors
      issue_to_actor = Promise.all(
        events.map do |issue_id, event|
          next Promise.resolve([issue_id, nil]) if event.nil?

          event.async_actor.then do |actor|
            [issue_id, actor]
          end
        end
      ).sync.to_h

      # Update the closed by for all of our issues
      issues.each do |issue|
        issue.closed_by = issue_to_actor[issue.id]
      end
    end

    def prefill_close_issue_reference_counts(issues, viewer = nil)
      pull_issues, issues = issues.partition(&:pull_request?)

      prefill_close_issue_reference_counts_for_issues(issues, viewer)
      prefill_close_issue_reference_counts_for_pulls(pull_issues, viewer)
    end

    def prefill_close_issue_reference_counts_for_issues(issues, viewer)
      return unless issues.any?
      issue_ids = issues.map(&:id)

      grouped_issue_list = list_xrefs_by_issue_id(issue_ids)

      # Find which of the connected pull requests are deemed viewable
      pull_ids = grouped_issue_list.values.flatten.uniq

      issue_ids_for_pulls = fetch_issue_ids_for_pulls(pull_ids, viewer)

      visible_prs_for_issues = Issue.legacy_visible_for(issue_ids_for_pulls, viewer: viewer).pluck(:pull_request_id)

      # For each issue, find which of its connected PRs are visible
      # and memoize the count on the issue instance.
      issues.each do |issue|
        pull_request_id_list = Array(grouped_issue_list[issue.id])
        issue.close_issue_references_count = (pull_request_id_list & visible_prs_for_issues).count
      end
    end

    def prefill_close_issue_reference_counts_for_pulls(pull_issues, viewer)
      return unless pull_issues.any?
      pull_request_ids = pull_issues.map(&:pull_request_id)

      grouped_pr_list = list_xrefs_by_pr_id(pull_request_ids)

      # Find which of the connected issues are deemed viewable
      issue_ids = grouped_pr_list.values.flatten.uniq
      visible_issues_for_prs = Issue.legacy_visible_for(issue_ids, viewer: viewer).pluck(:id)

      # For each issue, find which of its connected PRs are visible
      # and memoize the count on the issue instance.
      pull_issues.each do |pull_issue|
        issue_id_list = Array(grouped_pr_list[pull_issue.pull_request_id])
        pull_issue.close_issue_references_count = (issue_id_list & visible_issues_for_prs).count
      end
    end

    def list_xrefs_by_issue_id(issue_ids)
      # Find all the pull_request_ids connected to the issues via close_issue_references in batches
      result = CloseIssueReference
        .batched_scope(:issue_id, values: issue_ids, batch_size: batch_size)
        .execute do |scope|
          scope.async_pluck(:issue_id, :pull_request_id)
        end
        .flat_map(&:value)

      # Create a hash so results can easily be indexed later
      # Returns { issue_id: [pull_request_id1, pull_request_id2], issue_id2: [pull_request_id_3] }
      grouped_issue_list = result.each_with_object({}) do |(issue_id, pull_request_id), hash|
        hash[issue_id] ||= []
        hash[issue_id] << pull_request_id
      end

      grouped_issue_list
    end

    def list_xrefs_by_pr_id(pull_request_ids)
      # Find all the pull_request_ids connected to the issues via close_issue_references in batches
      result = CloseIssueReference
        .batched_scope(:pull_request_id, values: pull_request_ids, batch_size: batch_size)
        .execute do |scope|
          scope.async_pluck(:issue_id, :pull_request_id)
        end
        .flat_map(&:value)

      # Create a hash so results can easily be indexed later
      # Returns { pull_request_id1: [issue_id1, issue_id2], pull_request_id2: [issue_id_3] }
      grouped_pr_list = result.each_with_object({}) do |(issue_id, pull_request_id), hash|
        hash[pull_request_id] ||= []
        hash[pull_request_id] << issue_id
      end

      grouped_pr_list
    end

    def fetch_issue_ids_for_pulls(pull_ids, viewer)
      Issue
        .batched_scope(:pull_request_id, values: pull_ids, batch_size: batch_size)
        .execute do |scope|
          scope.async_pluck(:id)
        end
        .flat_map(&:value)
    end

    def batch_size
      BATCH_SIZE
    end
  end
end
