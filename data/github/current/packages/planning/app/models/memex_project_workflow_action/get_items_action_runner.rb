# typed: true
# frozen_string_literal: true

# This class is a scaffold for testing the piped workflow runner, will be fleshed out in a future PR
class MemexProjectWorkflowAction::GetItemsActionRunner < MemexProjectWorkflowAction::BaseActionRunner
  ACTION_TYPE = :get_items

  UPDATE_EVENT_TOPICS = %w(
    cp1-iad.ingest.github.v1.IssueUpdateMilestone
    github.memex_automation.v0.IssueUpdateEvent
    github.v1.PullRequestUpdate
    github.v1.IssueUpdateLabel
    github.v1.IssueUpdateAssignee
    github.v1.IssueUpdateIssueType
  )

  def run
    @query = @action.arguments["query"]
    @repository_id = @action.arguments["repositoryId"]

    log_duration do
      if @manual_run
        raise NotImplementedError, "Manual run not implemented for get_items action"
      else
        filter_items
      end
    end
  end

  private

  def memex_project
    @action.workflow&.memex_project
  end

  def last_updater
    @action.last_updater
  end

  def filter_items
    if should_run?
      items = @input.reject { |item| memex_project.memex_project_items.exists?(content_id: item.id) }
      MemexProjectWorkflowAction::ItemsFilter.filter_items(items, @query, repository_id: @repository_id)
    else
      []
    end
  end

  # Should any items be returned at all?
  def should_run?
    if FeatureFlag.vexi.enabled?(:memex_auto_add_automation_update_event_filter, default: true) && is_update_topic?
      return false unless update_topic_has_matching_query
    end

    if @repository_id.present? && memex_project && last_updater && memex_project.viewer_can_write?(last_updater)
      repo = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
        Repositories.domain.by_id(@repository_id)
      else
        Repository.find_by(id: @repository_id)
      end
      if repo
        repo.public? || last_updater.associated_repository_ids(repository_ids: [@repository_id])&.include?(@repository_id)
      end
    else
      false
    end
  end

  def topic
    topic_tag = @tags&.find { |tag| tag.include?("topic:") }&.match(/topic:(.*)/)
    topic_tag ? topic_tag[1] : nil
  end

  def is_update_topic?
    topic && UPDATE_EVENT_TOPICS.include?(topic)
  end

  def has_label_query?
    @query.match(MemexProjectWorkflowAction::ItemsFilter::LABEL_QUALIFIER)
  end

  def has_type_query?
    @query.match(MemexProjectWorkflowAction::ItemsFilter::ISSUE_TYPE_QUALIFIER)
  end

  def has_assignee_query?
    @query.match(MemexProjectWorkflowAction::ItemsFilter::ASSIGNEE_QUALIFIER)
  end

  # Check if has IssueUpdateAssignee or IssueUpdateLabel events
  # have a corresponding (labels, assignee, issue type) query that matches those topics and vice versa
  def update_topic_has_matching_query
    is_assignee_update = topic == "github.v1.IssueUpdateAssignee"
    is_label_update = topic == "github.v1.IssueUpdateLabel"
    is_type_update = topic == "github.v1.IssueUpdateIssueType"

    # IssueUpdateAssignee or IssueUpdateLabel or IssueUpdateIssueType events must have matching query
    if is_label_update || is_assignee_update || is_type_update
      is_label_update && has_label_query? || is_assignee_update && has_assignee_query? || is_type_update && has_type_query?
    # Other updates events should not have these queries
    elsif has_label_query? || has_assignee_query? || has_type_query?
      false
    else
      true
    end
  end
end
