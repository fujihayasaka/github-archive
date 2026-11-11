# typed: true
# frozen_string_literal: true

# handles executing actions against inputs and returns the results
class MemexProjectWorkflowAction::Runner
  RUNNERS_BY_ACTION_TYPE = {
    set_field: MemexProjectWorkflowAction::SetFieldActionRunner,
    get_items: MemexProjectWorkflowAction::GetItemsActionRunner,
    add_project_item: MemexProjectWorkflowAction::AddProjectItemActionRunner,
    get_project_items: MemexProjectWorkflowAction::GetProjectItemsActionRunner,
    archive_project_item: MemexProjectWorkflowAction::ArchiveProjectItemActionRunner,
    close_item: MemexProjectWorkflowAction::CloseItemActionRunner,
    get_sub_issues: MemexProjectWorkflowAction::GetSubIssuesActionRunner,
  }

  def self.run(**kwargs)
    new(**T.unsafe(kwargs)).run
  end

  def initialize(action:, input:, actor:, trigger_type: nil, tags: [], manual_run: false, content_types: nil)
    @action = action
    @input = input
    @actor = actor
    @trigger_type = trigger_type
    @manual_run = manual_run
    @tags = tags
    @content_types = content_types
  end

  def run
    # todo #projects-automation: track the action's execution
    klass = RUNNERS_BY_ACTION_TYPE[@action.action_type.to_sym]
    raise "no action found for action_type #{@action.action_type}" unless klass
    klass.run(
      action: @action,
      input: @input,
      actor: @actor,
      trigger_type: @trigger_type,
      tags: @tags,
      manual_run: @manual_run,
      content_types: @content_types)
  end
end
