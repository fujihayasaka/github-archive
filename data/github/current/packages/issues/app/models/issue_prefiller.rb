# typed: true
# frozen_string_literal: true

module IssuePrefiller
  include GitHub::Tracing

  class << self
    PREFILLS_FOR_ISSUES = [:labels, :assignees, :assignments, :pull_request, :milestone, :close_issue_references, :closed_by, :active_lock_reason, :sub_issue_list, :issue_dependency_list, :issue_types, :issue_field_values, :parent_issue_relation, :pinned_issue_comment]
    OPTIMIZED_PREFILL_FOR_ISSUES = [:labels, :assignees, :assignments, :pull_request, :milestone, :close_issue_references, :closed_by, :active_lock_reason, :sub_issue_list, :issue_dependency_list, :issue_types, :user, :repository, :author_association, :issue_field_values, :parent_issue_relation, :pinned_issue_comment]
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
      GitHub.tracer.in_span("issue_prefiller/prefill", kind: :internal) do
        only_prefill = only_prefill.map(&:to_sym) - exclude_prefills.map(&:to_sym)

        include_issue_types = only_prefill.include?(:issue_types)
        # If issue types are included, we need to preload the repository owner to see if issue types are enabled
        associations_to_prefill = include_issue_types ? [{ user: :profile }, { repository: :owner }] : [{ user: :profile }, :repository]
        associations_to_prefill << T.unsafe([:labels, :assignees, :assignments, :sub_issue_list, :issue_dependency_list, :parent_issue_relation] & only_prefill)
        associations_to_prefill << { assignee: :profile } if only_prefill.include?(:assignees)
        associations_to_prefill << { milestone: [:created_by, :repository] } if only_prefill.include?(:milestone)
        associations_to_prefill << :pull_request if only_prefill.include?(:pull_request)
        associations_to_prefill << { parent_issue_relation: [{ source: :repository }] } if only_prefill.include?(:parent_issue_relation)
        associations_to_prefill << { pinned_issue_comment: [:pinned_by, :issue_comment] } if only_prefill.include?(:pinned_issue_comment)

        GitHub::PrefillAssociations.prefill_associations(issues, associations_to_prefill, available_records: [repository]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

        if only_prefill.include?(:issue_field_values)
          IssueFieldValue.preload_for_issues(issues.to_a) if issues
        end

        if include_issue_types
          GitHub::PrefillAssociations.prefill_batch_method(issues, :issue_type)
        end

        prefill_close_issue_reference_counts(issues, current_user) if only_prefill.include?(:close_issue_references)

        if only_prefill.include?(:closed_by)
          prefill_closed_by(issues, viewer: current_user)
        end

        if only_prefill.include?(:active_lock_reason)
          prefill_active_lock_reason(issues)
        end
      end
    end

    # Otimized version of the above
    def optimized_prefill(issues, repository: nil, only_prefill: OPTIMIZED_PREFILL_FOR_ISSUES, exclude_prefills: [], current_user: nil, tags: [], mime_param: nil, available_records: [], disable_issues_graph: false)
      GitHub.tracer.in_span("issue_prefiller/optimized_prefill", kind: :internal) do
        only_prefill = only_prefill.map(&:to_sym) - exclude_prefills.map(&:to_sym)

        associations_to_prefill = T.unsafe([:labels, :assignments, :sub_issue_list, :issue_dependency_list, :parent_issue_relation] & only_prefill)
        associations_to_prefill << :user
        if only_prefill.include?(:user)
          associations_to_prefill << { user: :profile }
        end
        if only_prefill.include?(:repository)
          associations_to_prefill << :repository
          associations_to_prefill << { repository: :owner }
        end
        if only_prefill.include?(:assignees)
          associations_to_prefill << :assignees
          associations_to_prefill << { assignee: :profile }
        end
        if only_prefill.include?(:milestone)
          associations_to_prefill << :milestone
          associations_to_prefill << { milestone: [:created_by, :repository] }
        end
        if only_prefill.include?(:pull_request)
          associations_to_prefill << :pull_request
          # If we are pre-filling pull requests, we also need to pre-fill the user and repository
          # associated with the pull request to ensure that we can access the pull request's user and repository.
          associations_to_prefill << { pull_request: [:user, :repository] }
        end
        if only_prefill.include?(:parent_issue_relation)
          associations_to_prefill << { parent_issue_relation: [{ source: :repository }] }
        end
        if only_prefill.include?(:pinned_issue_comment)
          associations_to_prefill << { pinned_issue_comment: [:pinned_by, :issue_comment] }
        end
        available_records << repository if repository
        available_records << current_user if current_user

        GitHub::PrefillAssociations.prefill_associations(issues, associations_to_prefill, available_records: available_records.compact) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

        if only_prefill.include?(:issue_field_values)
          IssueFieldValue.preload_for_issues(issues.to_a) if issues
        end

        if only_prefill.include?(:issue_types)
          GitHub::PrefillAssociations.prefill_batch_method(issues, :optimized_issue_type)
        end

        if only_prefill.include?(:close_issue_references)
          prefill_close_issue_reference_counts(issues, current_user)
        end

        if only_prefill.include?(:closed_by)
          prefill_closed_by(issues, viewer: current_user)
        end

        if only_prefill.include?(:active_lock_reason)
          prefill_active_lock_reason(issues)
        end

        if only_prefill.include?(:author_association)
          preload_author_associations(issues, current_user)
        end

        if mime_param == :full || mime_param == :html
          GitHub::PrefillAssociations.prefill_batch_method(issues,
            :prelude_body_html,
            { context: { disable_issues_graph: disable_issues_graph } }
          )
        end
        if mime_param == :full || mime_param == :text
          GitHub::PrefillAssociations.prefill_batch_method(issues,
            :prelude_body_text,
            { context: { disable_issues_graph: disable_issues_graph } }
          )
        end
      end
    end

    def preload_author_associations(issues, current_user)
      GitHub.tracer.in_span("issue_prefiller/preload_author_associations", kind: :internal) do
        promises = issues.map do |associable|
          CommentAuthorAssociation.new(comment: associable, viewer: current_user).async_to_sym_candidate.then do |sym|
            next if associable.instance_variable_defined?(:@author_association_symbol)

            associable.preload_attr(:author_association_symbol, sym)
          end
        end

        Promise.all(promises).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end

    def optimized_preload_author_associations(associables, current_user)
      # Get a unique list of the associables, indexed by [user_id, repository_id]
      uniq_user_repo_associables = associables.uniq { |a| [a.user_id, a.repository_id] }
                                            .index_by { |a| [a.user_id, a.repository_id] }

      # Create a cache for our promises
      uniq_cached_promises = T.let({}, T::Hash[[Integer, Integer], Promise[Symbol]])

      uniq_user_repo_associables.each do |(user_id, repo_id), associable|
        next if associable.instance_variable_defined?(:@author_association_symbol)

        uniq_cached_promises[[user_id, repo_id]] ||= CommentAuthorAssociation.new(comment: associable, viewer: current_user).async_to_sym_candidate
        uniq_cached_promises[[user_id, repo_id]].then do |sym|
          associable.preload_attr(:author_association_symbol, sym)
        end
      end

      # Iterate across all the associables and fetch the promise from the cache
      promises = associables.map do |associable|
        next Promise.resolve(nil) if associable.instance_variable_defined?(:@author_association_symbol)
        uniq_cached_promises[[associable.user_id, associable.repository_id]]
      end

      Promise.all(promises).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    private

    def prefill_closed_by(issues, viewer: nil)
      if FeatureFlag.vexi.enabled?(:pulls_exclude_closed_by_on_state_open, viewer, default: false)
        closed_issues = []

        issues.each do |issue|
          if issue.closed?
            closed_issues << issue
          else
            # Memoize nil for open issues so serializer access does not trigger
            # per-record fallback loads via Issue#closed_by.
            issue.closed_by = nil
          end
        end

        return if closed_issues.empty?

        issues = closed_issues
      end

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

    # Batch loads the most recent "locked" issue event (and its detail, which
    # holds the lock reason) for all locked issues so that serializing a
    # collection does not trigger one Issue#active_lock_reason query per issue.
    def prefill_active_lock_reason(issues)
      locked_issues = issues.select(&:locked?)
      return if locked_issues.empty?

      # IssueEvent.locks is ordered by id ASC; IssueEvent's default scope
      # eager-loads :issue_event_detail, so this resolves to a single
      # issue_events query plus a single batched issue_event_details query
      # regardless of how many issues are locked.
      events_by_issue = IssueEvent.locks
        .where(issue_id: locked_issues.map(&:id))
        .group_by(&:issue_id)

      locked_issues.each do |issue|
        issue.active_lock_reason = events_by_issue[issue.id]&.last&.lock_reason
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
