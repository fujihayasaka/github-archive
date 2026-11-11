# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Reponsible for finding batches of last-updated related workflows and enqueing them to run.
# Runs every 12 hours
class MemexProjectWorkflowScheduledRunnerJob < BatchedJob
  include MemexHydroProjectAutomation::Instrumentation::ScheduledRunner

  BATCH_SIZE = 100
  TARGET_ACTIONS = [:get_project_items]
  TIME_BOUND_QUALIFIERS = /(last-updated|updated):/i

  queue_as :memex_project_scheduled_workflow_runner
  schedule interval: GitHub.projects_new_workflow_scheduled_runner_schedule
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  exempt_from_tenant_context_requirement

  def next_batch(offset_item_id: 0, **options)
    related_actions offset_item_id
  end

  def process_batch(actions, initial_start:, **_args)
    return unless GitHub.projects_automation_enabled?

    valid_actions = actions.select do |action|
      action.arguments["query"]&.match(TIME_BOUND_QUALIFIERS)
    end

    actor = Apps::Privileged::MemexAutomation.bot

    workflow_ids = valid_actions.map(&:memex_project_workflow_id).uniq
    workflows = enabled_workflows(workflow_ids)
    return unless workflows.present?

    log_workflows_matched(workflows: workflows, actor: actor)
    workflows.each do |workflow|
      input = []
      MemexProjectWorkflowRunnerJob.perform_later(
        workflow_id: workflow.id,
        input: input,
        actor_id: actor.id,
        tags: stats_tags_default,
        event_time: initial_start,
        manual_run: true,
      )
      log_workflow_enqueued(workflow: workflow, input: input, actor: actor)
    end
  end

  private

  # returns workflows that are both enabled and are owned by actors in the FF
  def enabled_workflows(workflow_ids)
    MemexProjectWorkflow.throttle do
      MemexProjectWorkflow.
        includes(memex_project: :owner).
        where(id: workflow_ids, enabled: true)
    end
  end

  def related_actions(action_offset_id = 0)
    MemexProjectWorkflowAction.throttle do
      MemexProjectWorkflowAction.
        where(action_type: TARGET_ACTIONS).
        where("id > ?", action_offset_id).
        order(id: :asc).
        limit(BATCH_SIZE)
    end
  end
end
