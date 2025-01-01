# typed: true
# frozen_string_literal: true

# Base class for all piped hydro project automation jobs (auto archive, auto add, and set_field variants)
class MemexHydroProjectAutomation::HydroBasePipedProjectAutomationJob < HydroMessageJob
  extend T::Sig

  BATCH_SIZE = 1_000

  include MemexProjectWorkflow::WorkflowQueries
  include MemexHydroProjectAutomation::Instrumentation

  retry_on_dirty_exit
  retry_on *Resiliency::Response::UnavailableExceptions
  retry_on Freno::Throttler::Error, Freno::Error, Freno::Throttler::WaitedTooLong

  # Given a hydro message's content, enqueues a job run for each related workflow by finding project items
  # referencing the content and then finding the workflows that are configured to run for the project
  sig { params(repository_id: Integer, content_id: Integer, content_type: String, target_action: Symbol, actor: User, trigger_type: T.nilable(Symbol), sub_issue_id: T.nilable(Integer)).void }
  def enqueue_related_workflows(repository_id, content_id, content_type, target_action, actor, trigger_type = nil, sub_issue_id = nil)
    found_project_items = T.let([], T::Array[MemexProjectItem])
    found_workflows = T.let([], T::Array[MemexProjectWorkflow])
    project_items_matching_content(repository_id, content_id, content_type) do |project_items|
      seen_items, seen_workflows = enqueue_workflows_for_project_items(project_items, target_action, actor, trigger_type, content_id, content_type, sub_issue_id)
      found_project_items += seen_items
      found_workflows += seen_workflows
    end

    return skip_no_matches if found_project_items.empty?
    return skip_no_workflows if found_workflows.empty?

    log_success
  end

  # Given a project item, enqueues a job run for its related workflows
  sig { params(project_item: MemexProjectItem, target_action: Symbol, actor: User, trigger_type: T.nilable(Symbol)).void }
  def enqueue_workflows_for_project_item(project_item, target_action, actor, trigger_type = nil)
    seen_items, seen_workflows = enqueue_workflows_for_project_items([project_item], target_action, actor, trigger_type)

    return skip_no_matches if seen_items.empty?
    return skip_no_workflows if seen_workflows.empty?

    log_success
  end

  # Is a given project item processable by this job? Override to allow workflows to be run.
  # See HydroArchiveProjectItemOnCloseAutomationJob for an example
  private def project_item_processable?(project_item)
    raise NotImplementedError
  end

  sig { params(project_items: T::Array[MemexProjectItem], target_action: Symbol, actor: User, trigger_type: T.nilable(Symbol), content_id: T.nilable(Integer), content_type: T.nilable(String), sub_issue_id: T.nilable(Integer)).returns([T::Array[MemexProjectItem], T::Array[MemexProjectWorkflow]]) }
  private def enqueue_workflows_for_project_items(
    project_items,
    target_action,
    actor,
    trigger_type = nil,
    content_id = nil,
    content_type = nil,
    sub_issue_id = nil
  )
    found_project_items = T.let([], T::Array[MemexProjectItem])
    found_workflows = T.let([], T::Array[MemexProjectWorkflow])

    processable_project_items = project_items.select do |project_item|
      project_item_processable?(project_item)
    end
    return [found_project_items, found_workflows] if processable_project_items.empty?

    found_project_items += processable_project_items
    workflows = related_workflows(processable_project_items, target_action, trigger_type)
    return [found_project_items, found_workflows] if workflows.empty?

    found_workflows += workflows
    log_workflows(
      content_id: content_id,
      content_type: content_type,
      workflows: workflows,
      actor: actor
    )
    workflows_by_project_id = workflows.group_by { |w| w.memex_project_id }
    # an issue/pr can only be added once to a project, so a flat hash is safe:
    project_item_by_project_id = T.let({}, T::Hash[T.nilable(Integer), MemexProjectItem])
    project_item_by_project_id = processable_project_items.reduce(project_item_by_project_id) do |hash, project_item|
      hash[project_item.memex_project_id] = project_item
      hash
    end

    projects = processable_project_items.map(&:memex_project).uniq.compact
    projects.each do |project|
      project_workflows = workflows_by_project_id[project.id]
      next unless project_workflows.present?

      project_workflows.each do |workflow|
        project_item = project_item_by_project_id[project.id]
        next unless project_item.present?
        # Draft issues are supported as though they are issues through the workflow configuration
        configured_content_type = if project_item.content_type == MemexProjectItem::DRAFT_ISSUE_TYPE
          MemexProjectItem::ISSUE_TYPE
        else
          project_item.content_type
        end
        next unless workflow.content_types.include?(configured_content_type)

        input = get_input(project_item, trigger_type, sub_issue_id)
        MemexProjectWorkflowRunnerJob.perform_later(
          workflow_id: workflow.id,
          input: input,
          actor_id: actor.id,
          tags: stats_tags_default,
          event_time: Time.at(timestamp_nano),
          manual_run: false,
        )
        log_workflow_enqueued(workflow: workflow, input: input, actor: actor)
      end
    end

    [found_project_items, found_workflows]
  end

  # Get input for workflows based on whether we're working with sub-issues or not
  sig do
    params(
      project_item: MemexProjectItem,
      trigger_type: T.nilable(Symbol),
      sub_issue_id: T.nilable(Integer)
    ).returns(T::Array[[T.nilable(String), T.nilable(Integer)]])
  end
  private def get_input(project_item, trigger_type = nil, sub_issue_id = nil)
    return [[project_item.class.name, project_item.id]] unless trigger_type == :sub_issues
    return [[MemexProjectItem::ISSUE_TYPE, sub_issue_id]] if sub_issue_id.present?

    project_item.content.try(:sub_issues).try(:map) { |sub_issue| [MemexProjectItem::ISSUE_TYPE, sub_issue.id] } || []
  end

  # Find project items that matches content information in batches
  sig { params(repository_id: Integer, content_id: Integer, content_type: String, block: T.proc.params(arg0: T::Array[MemexProjectItem]).void).returns(T.untyped) }
  private def project_items_matching_content(repository_id, content_id, content_type, &block)
    with_read do
      MemexProjectItem.throttle do
        MemexProjectItem
          .where(repository_id: repository_id, content_id: content_id, content_type: content_type)
          # prevents n+1 queries for feature flag checks against the project owner
          .includes(memex_project: :owner)
          .find_in_batches(batch_size: BATCH_SIZE) do |project_items|
            yield project_items
          end
      end
    end
  end

  # Find workflows that match the given project items, target action and optional trigger type
  sig { params(project_items: T::Array[MemexProjectItem], target_action: Symbol, trigger_type: T.nilable(Symbol)).returns(T::Array[MemexProjectWorkflow]) }
  private def related_workflows(project_items, target_action, trigger_type = nil)
    project_ids = project_items.map(&:memex_project_id).uniq
    with_read do
      # actions do not know about projects, so we need to find all enabled workflow_ids for the projects first
      workflow_where_params = { memex_project_id: project_ids, enabled: true }
      if trigger_type
        workflow_where_params[:trigger_type] = trigger_type
      end
      workflow_ids = MemexProjectWorkflow
        .where(**workflow_where_params)
        .select(:id)
        .distinct

      # then find all applicable actions that match the project's workflows
      applicable_workflow_ids = MemexProjectWorkflowAction
        .where(action_type: target_action, memex_project_workflow_id: workflow_ids)
        .select(:memex_project_workflow_id)
        .distinct

      # finally load the workflows
      MemexProjectWorkflow
        .where(id: applicable_workflow_ids)
        .to_a
    end
  end
end
