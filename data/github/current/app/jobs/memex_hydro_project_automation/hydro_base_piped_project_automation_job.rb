# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Base class for all piped hydro project automation jobs (auto archive, auto add, and set_field variants)
class MemexHydroProjectAutomation::HydroBasePipedProjectAutomationJob < HydroMessageJob

  BATCH_SIZE = 1_000
  MAX_WORKFLOWS_PER_BATCH = 1_000

  include MemexProjectWorkflow::WorkflowQueries
  include MemexHydroProjectAutomation::Instrumentation
  include MemexHydroProjectAutomation::ProjectItemStateEvaluator

  retry_on_dirty_exit
  retry_on *T.unsafe(Resiliency::Response::UnavailableExceptions)
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

    log_workflows(
      content_id: content_id,
      content_type: content_type,
      workflows: workflows,
      actor: actor
    )
    workflows_by_project_id = workflows.group_by { |w| w.memex_project_id }

    # one project can have multiple project items.
    # {307 => [#<MemexProjectItem id: 366, memex_project_id: 307 ...>, #<MemexProjectItem id: 367, memex_project_id: 307 ...>]}
    project_items_by_project_id = processable_project_items.group_by(&:memex_project_id)

    projects = processable_project_items.map(&:memex_project).uniq.compact
    projects.each do |project|
      project_workflows = workflows_by_project_id[project.id]
      next unless project_workflows.present?

      project_workflows.each do |workflow|
        project_items_for_project = T.must(project_items_by_project_id[project.id])
        next unless project_items_for_project.present?

        allowed_types = workflow.content_types.to_set

        input = project_items_for_project.flat_map do |project_item|
          # Draft issues are supported as though they are issues through the workflow configuration
          configured_content_type =
          if project_item.content_type == MemexProjectItem::ContentType::DraftIssue.serialize
            MemexProjectItem::ContentType::Issue.serialize
          else
            project_item.content_type
          end

          next [] unless allowed_types.include?(configured_content_type)
          get_input(project_item, trigger_type, sub_issue_id)
        end

        next if input.empty?

        found_workflows << workflow
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

  # Get input for workflows based on whether we're working with sub-issues or not. Overrideable to allow automations
  # to better control the input for specific cases and trigger types.
  sig do
    overridable.params(
      project_item: MemexProjectItem,
      trigger_type: T.nilable(Symbol),
      sub_issue_id: T.nilable(Integer)
    ).returns(T::Array[[String, Integer]])
  end
  private def get_input(project_item, trigger_type = nil, sub_issue_id = nil)
    return [[T.must(project_item.class.name), project_item.id]] unless trigger_type == :sub_issues
    return [[MemexProjectItem::ContentType::Issue.serialize, sub_issue_id]] if sub_issue_id.present?

    project_item.content.try(:sub_issues).try(:map) { |sub_issue| [MemexProjectItem::ContentType::Issue.serialize, sub_issue.id] } || []  # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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

  sig { params(memex_project_item_ids: T::Array[Integer], block: T.proc.params(arg0: T::Array[MemexProjectItem]).void).returns(T.untyped) }
  private def select_project_items(memex_project_item_ids, &block)
    with_read do
      MemexProjectItem.throttle do
        MemexProjectItem
        .where(id: memex_project_item_ids)
        .find_in_batches(batch_size: BATCH_SIZE) do |project_items|
          yield project_items
        end
      end
    end
  end

  sig { params(project_items: T::Array[MemexProjectItem]).returns(T::Array[MemexProjectItem]) }
  private def select_project_items_with_sub_issues(project_items)
    issue_items = project_items.select { |item| item.content_type == "Issue" && item.issue_id.present? }
    return [] if issue_items.empty?

    issue_ids = issue_items.map(&:issue_id).compact.uniq
    issue_ids_with_sub_issues = with_read do
      SubIssue.throttle do
        SubIssue
          .where(source_issue_id: issue_ids)
          .distinct
          .pluck(:source_issue_id)
      end
    end

    return [] if issue_ids_with_sub_issues.empty?

    issue_id_set = issue_ids_with_sub_issues.to_set
    issue_items.select { |item| issue_id_set.include?(item.issue_id) }
  end

  private def select_issue_ids_with_sub_issues(issue_ids)
    with_read do
      SubIssue.throttle do
        SubIssue
        .where(source_issue_id: issue_ids)
        .distinct
        .pluck(:source_issue_id)
        .each_slice(BATCH_SIZE) do |source_issue_ids|
          yield source_issue_ids
        end
      end
    end
  end

  # Fetch all enabled workflows for the given projects
  # This is useful for bulk operations where you want to preload workflows
  # and then filter them in memory for different actions/triggers
  #
  # Projects typically have ~10 enabled workflows, though users can create custom workflows.
  # MAX_WORKFLOWS_PER_BATCH is a defensive measure to prevent unbounded queries while being
  # generous enough to support ~100 projects with typical usage or ~10 projects with heavy
  # custom workflow usage.
  #
  # @raise [RuntimeError] if the number of workflows exceeds MAX_WORKFLOWS_PER_BATCH
  sig { params(project_ids: T::Array[Integer]).returns(T::Array[MemexProjectWorkflow]) }
  def enabled_workflows_for_projects(project_ids)
    return [] if project_ids.empty?

    with_read do
      workflows = MemexProjectWorkflow
        .where(memex_project_id: project_ids, enabled: true)
        .limit(MAX_WORKFLOWS_PER_BATCH)
        .includes(:actions)
        .to_a

      if workflows.size >= MAX_WORKFLOWS_PER_BATCH
        raise "Workflow limit of #{MAX_WORKFLOWS_PER_BATCH} exceeded for project_ids=#{project_ids.inspect}. " \
              "Found #{workflows.size} workflows. This may indicate too many projects being processed at once."
      end

      workflows
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
