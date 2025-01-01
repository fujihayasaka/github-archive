# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

class ProcessProjectWorkflowsJob < ApplicationJob
  # Use primary connection for writing data to project_workflows tables.
  use_primaries ApplicationRecord::Mysql1,
  # Use primary connection for writing data to issue_events, issue_event_details tables.
  ApplicationRecord::IssuesPullRequests

  include ActiveJob::InitiallyEnqueuedAt

  class WorkflowError < StandardError; end

  queue_as :project_workflows

  retry_on ProjectWorkflow::MissingIssueObject, wait: :polynomially_longer, attempts: 3
  retry_on_dirty_exit

  locked_by timeout: 1.hour, key: ->(job) {
    trigger_type = job.arguments[0]
    trigger_attributes = job.arguments[1]
    key = [trigger_type] + trigger_attributes.stringify_keys.slice("actor_id", "issue_id", "project_card_id").to_a
    key.flatten.map(&:to_s).join(",")
  }

  BATCH_SIZE = 100

  def perform(trigger_type, trigger_attributes = {}, offset_id = 0, run_workflows_count = 0, enqueued_at = initially_enqueued_at)
    start_time = Time.current
    tags = ["trigger:external", "trigger_type:#{trigger_type}"]

    unless ProjectWorkflow::EXTERNAL_TRIGGERS.include?(trigger_type)
      GitHub.dogstats.increment("job.process_project_workflows.invalid_trigger_type", tags: tags)
      return
    end

    actor_id = trigger_attributes[:actor_id]
    issue_id = trigger_attributes[:issue_id]
    project_card_id = trigger_attributes[:project_card_id]

    unless actor_id
      GitHub.dogstats.increment("job.process_project_workflows.missing_actor_id", tags: tags)
      return
    end
    unless issue_id
      GitHub.dogstats.increment("job.process_project_workflows.missing_issue_id", tags: tags)
      return
    end

    if run_workflows_count == 0
      delay_ms = (start_time - enqueued_at) * 1_000
      GitHub.dogstats.distribution("job.dist.process_project_workflows.time_enqueued", delay_ms, tags: tags)
    end

    actor = User.find_by_id(actor_id)
    unless actor.present?
      GitHub.dogstats.increment("job.process_project_workflows.missing_actor_object", tags: tags)
      actor = User.ghost
    end

    tags << "employee_actor:#{actor.employee?}"

    issue = Issue.find_by_id(issue_id)
    unless issue.present?
      GitHub.dogstats.increment("job.process_project_workflows.missing_issue_object", tags: tags)

      raise ProjectWorkflow::MissingIssueObject.new(
        "trigger_type: #{trigger_type}, actor_id: #{actor_id}, " +
        "issue_id: #{issue_id}"
      )
    end

    trigger = ProjectWorkflow.filter_trigger(trigger_type, issue, nil)
    unless trigger
      GitHub.dogstats.increment("job.process_project_workflows.irrelevant_trigger", tags: tags)
      return
    end

    workflows = ProjectWorkflow.externally_triggered_workflows(trigger, issue, project_card_id: project_card_id, offset_id: offset_id, batch_size: BATCH_SIZE, tags: tags)
    unless workflows.present?
      GitHub.dogstats.increment("job.process_project_workflows.missing_workflows", tags: tags)
      return
    end

    workflows.each do |workflow|
      begin
        workflow.run(issue: issue, actor: actor) if workflow.should_run?(issue: issue, as_of: enqueued_at)
        run_workflows_count += 1
      rescue StandardError => err # rubocop:todo Lint/GenericRescue
        Failbot.report(err.with_redacting!)
      end
    end

    unless last_batch(workflows)
      max_id = workflows.map(&:id).max
      ProcessProjectWorkflowsJob.perform_later(trigger_type, trigger_attributes, max_id, run_workflows_count, enqueued_at)
    end
  rescue ActiveRecord::ActiveRecordError => e
    Failbot.report(WorkflowError.new("trigger_type: #{trigger_type}, issue_id: #{issue_id}, actor_id: #{actor_id}, project_card_id: #{project_card_id}"), app: "github-projects")
  ensure
    record_single_run(start_time, tags)
    record_total_duration(enqueued_at, run_workflows_count, tags) if last_batch(workflows)
  end

  private

  def last_batch(workflows)
    return true if workflows.nil?

    workflows&.size < BATCH_SIZE
  end

  def record_single_run(start_time, tags)
    GitHub.dogstats.distribution_timing_since("job.dist.process_project_workflows.time", start_time, tags: tags)
  end

  def record_total_duration(enqueue_time, total_workflows_count, tags)
    GitHub.dogstats.count("job.process_project_workflows.processed", total_workflows_count, tags: tags)
    GitHub.dogstats.distribution_timing_since("job.dist.process_project_workflows.total_time", enqueue_time, tags: tags)
    # Former stats metric. Keeping for data consistency.
    GitHub.dogstats.count("project_workflow.processed", total_workflows_count, tags: tags)
  end
end
