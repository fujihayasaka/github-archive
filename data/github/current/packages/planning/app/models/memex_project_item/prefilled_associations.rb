# typed: strict
# frozen_string_literal: true

class MemexProjectItem::PrefilledAssociations
  sig { returns(T.nilable(MemexProjectColumn)) }
  attr_reader :title_column

  sig do
    params(
      title_column: T.nilable(MemexProjectColumn),
      draft_issue_ids_by_item_id: T::Hash[Integer, Integer],
      assignees_by_issue_id: T::Hash[Integer, T::Array[User]],
      reviewers_by_issue_id: T::Hash[Integer, T::Array[T::Hash[T.untyped, T.untyped]]],
      assignees_by_draft_issue_id: T::Hash[Integer, T::Array[User]],
      labels_by_issue_id: T::Hash[Integer, T::Array[Label]],
      linked_pull_requests_by_issue_id: T::Hash[Integer, T::Array[PullRequest]],
      repositories_by_issue_id: T::Hash[Integer, Repository],
      milestones_by_issue_id: T::Hash[Integer, T.nilable(T::Hash[T.untyped, T.untyped])],
      item_completions_by_issue_id: T::Hash[Integer, T::Hash[T.untyped, T.untyped]],
      issue_types_by_issue_id: T::Hash[Integer, T.nilable(IssueType)],
      tracked_by_items_by_issue_id: T::Hash[Integer, T::Array[TasklistBlocks::Issue]],
      parent_issues_by_issue_id: T::Hash[Integer, T.nilable(Issue)],
      sub_issues_progress_by_issue_id: T::Hash[Integer, T.nilable(SubIssueList)],
      partial_failures: T::Array[T::Hash[T.untyped, T.untyped]],
      global_relay_ids_by_issue_id: T::Hash[Integer, String]
    ).void
  end
  def initialize(
      title_column: nil,
      draft_issue_ids_by_item_id: {},
      assignees_by_issue_id: {},
      reviewers_by_issue_id: {},
      assignees_by_draft_issue_id: {},
      labels_by_issue_id: {},
      linked_pull_requests_by_issue_id: {},
      repositories_by_issue_id: {},
      milestones_by_issue_id: {},
      item_completions_by_issue_id: {},
      issue_types_by_issue_id: {},
      tracked_by_items_by_issue_id: {},
      parent_issues_by_issue_id: {},
      sub_issues_progress_by_issue_id: {},
      partial_failures: [],
      global_relay_ids_by_issue_id: {}
    )
    @title_column = title_column
    @draft_issue_ids_by_item_id = draft_issue_ids_by_item_id
    @assignees_by_issue_id = assignees_by_issue_id
    @reviewers_by_issue_id = reviewers_by_issue_id
    @assignees_by_draft_issue_id = assignees_by_draft_issue_id
    @labels_by_issue_id = labels_by_issue_id
    @linked_pull_requests_by_issue_id = linked_pull_requests_by_issue_id
    @repositories_by_issue_id = repositories_by_issue_id
    @milestones_by_issue_id = milestones_by_issue_id
    @item_completions_by_issue_id = item_completions_by_issue_id
    @issue_types_by_issue_id = issue_types_by_issue_id
    @tracked_by_items_by_issue_id = tracked_by_items_by_issue_id
    @parent_issues_by_issue_id = parent_issues_by_issue_id
    @sub_issues_progress_by_issue_id = sub_issues_progress_by_issue_id
    @partial_failures = partial_failures
    @merged_partial_failures = T.let(nil, T.nilable(T::Array[T::Hash[T.untyped, T.untyped]]))
    @global_relay_ids_by_issue_id = global_relay_ids_by_issue_id
  end

  # All MemexProjectItem content types can have assignees, do not need to return nil to signal that assignees are
  # unsupported by the content type.
  sig { params(item: MemexProjectItem).returns(T::Array[User]) }
  def assignees(item)
    assignees = if item.issue_id?
      @assignees_by_issue_id[item.issue_id]
    elsif (draft_id = draft_issue_id(item))
      @assignees_by_draft_issue_id[draft_id]
    end

    Array.wrap(assignees)
  end

  sig { params(item: MemexProjectItem).returns(T.nilable(T::Array[T::Hash[T.untyped, T.untyped]])) }
  def reviewers(item)
    @reviewers_by_issue_id[item.issue_id]
  end

  sig { params(item: MemexProjectItem).returns(T.nilable(T::Array[Label])) }
  def labels(item)
    return if item.draft_issue?

    Array.wrap(@labels_by_issue_id[item.issue_id])
  end

  sig { params(item: MemexProjectItem).returns(T.nilable(T::Array[PullRequest])) }
  def linked_pull_requests(item)
    @linked_pull_requests_by_issue_id[item.issue_id]
  end

  sig { params(item: MemexProjectItem).returns(T.nilable(T::Array[TasklistBlocks::Issue])) }
  def tracked_by_items(item)
    @tracked_by_items_by_issue_id[item.issue_id]
  end

  sig { params(item: MemexProjectItem).returns(T.nilable(Repository)) }
  def repository(item)
    @repositories_by_issue_id[item.issue_id]
  end

  sig { params(item: MemexProjectItem).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  def milestone(item)
    @milestones_by_issue_id[item.issue_id]
  end

  sig { params(item: MemexProjectItem).returns(T.nilable(Integer)) }
  def draft_issue_id(item)
    @draft_issue_ids_by_item_id[item.id]
  end

  sig { params(item: MemexProjectItem).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  def completion(item)
    @item_completions_by_issue_id[item.issue_id]
  end

  sig { params(item: MemexProjectItem).returns(T.nilable(IssueType)) }
  def issue_type(item)
    @issue_types_by_issue_id[item.issue_id]
  end

  sig { params(item: MemexProjectItem).returns(T.nilable(Issue)) }
  def parent_issue(item)
    @parent_issues_by_issue_id[item.issue_id]
  end

  sig { params(item: MemexProjectItem).returns(T.nilable(SubIssueList)) }
  def sub_issues_progress(item)
    @sub_issues_progress_by_issue_id[item.issue_id]
  end

  sig { params(item: MemexProjectItem).returns(T.nilable(String)) }
  def global_relay_id(item)
    @global_relay_ids_by_issue_id[item.issue_id]
  end

  sig do
    params(
      column_name: T.nilable(T.any(String, Integer))
    ).returns(T.nilable(T.any(T::Array[T::Hash[T.untyped, T.untyped]], T::Hash[T.untyped, T.untyped])))
  end
  def partial_failures(column_name = nil)
    merged_partial_failures = if @merged_partial_failures
      @merged_partial_failures
    else
      @merged_partial_failures = @partial_failures.reduce([]) do |sum, partial_failure|
        index = sum.index { |pf| pf[:memexProjectColumn] == partial_failure[:memex_project_column] }
        if index != nil
          sum[index][:message].concat(". ", partial_failure[:message])
          sum
        else
          sum.push({
            memexProjectColumn: partial_failure[:memex_project_column],
            message: partial_failure[:message]
          })
        end
      end
    end
    return merged_partial_failures unless column_name && merged_partial_failures

    merged_partial_failures.find { |pf| pf[:memexProjectColumn] == column_name }
  end
end
