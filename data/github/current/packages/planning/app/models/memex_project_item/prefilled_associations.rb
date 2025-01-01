# typed: true
# frozen_string_literal: true

class MemexProjectItem::PrefilledAssociations
  attr_reader :title_column

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
    @merged_partial_failures = nil
    @global_relay_ids_by_issue_id = global_relay_ids_by_issue_id
  end

  def assignees(item, default_value: [])
    # if the item id is an issue, use that id to find assignees
    if item.issue_id.present?
      return @assignees_by_issue_id.fetch(item.issue_id, default_value)
    end

    # otherwise, use the draft issue id to find assignees
    if draft_issue_id(item).present?
      return @assignees_by_draft_issue_id.fetch(draft_issue_id(item), default_value)
    end

    default_value
  end

  def reviewers(item, default_value: [])
    @reviewers_by_issue_id.fetch(item.issue_id, default_value)
  end

  def labels(item, default_value: [])
    @labels_by_issue_id.fetch(item.issue_id, default_value)
  end

  def linked_pull_requests(item, default_value: [])
    @linked_pull_requests_by_issue_id.fetch(item.issue_id, default_value)
  end

  def tracked_by_items(item, default_value: [])
    @tracked_by_items_by_issue_id.fetch(item.issue_id, default_value)
  end

  def repository(item)
    @repositories_by_issue_id.fetch(item.issue_id, nil)
  end

  def milestone(item)
    @milestones_by_issue_id.fetch(item.issue_id, nil)
  end

  def draft_issue_id(item)
    @draft_issue_ids_by_item_id.fetch(item.id, nil)
  end

  def completion(item)
    @item_completions_by_issue_id.fetch(item.issue_id, nil)
  end

  def issue_type(item)
    @issue_types_by_issue_id.fetch(item.issue_id, nil)
  end

  def parent_issue(item)
    @parent_issues_by_issue_id.fetch(item.issue_id, nil)
  end

  def sub_issues_progress(item)
    @sub_issues_progress_by_issue_id.fetch(item.issue_id, nil)
  end

  def global_relay_id(item)
    @global_relay_ids_by_issue_id.fetch(item.issue_id, nil)
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
    column_partial_failure = merged_partial_failures.find { |pf| pf[:memexProjectColumn] == column_name }
    column_partial_failure if column_partial_failure
  end
end
