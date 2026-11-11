# typed: false
# frozen_string_literal: true

module Api::App::ActionsWorkflowsHelper
  private

  def workflows(repo, fetch_required_workflows: false)
    workflows = if fetch_required_workflows
      repo.workflows.not_deleted.required
    else
      repo.workflows.not_deleted.non_required
    end

    paginated_workflows = if current_user&.spammy?
      paginate_rel(workflows.spammer_viewable_workflows(current_user&.id))
    elsif current_user&.site_admin?
      paginate_rel(workflows)
    else
      paginate_rel(workflows.viewable_workflows)
    end

    paginated_workflows
  end

  def billing_payload_for_workflow(workflow, repository)
    owner = repository.owner
    starting_at = owner.current_metered_billing_cycle_starts_at
    ending_at = owner.next_metered_billing_cycle_starts_at

    lines = workflow.billing_usage_line_items(starting_at, ending_at)
    environments = lines.map { |line| line.job_runtime_environment }.uniq
    payload = {
      billable: {}
    }
    environments.each do |environment|
      payload[:billable][environment] = billing_timing_for_environment(lines, environment)
    end

    payload
  end

  def billing_timing_for_environment(lines, environment)
    env_lines = lines.select { |line| line.job_runtime_environment == environment }
    milliseconds = env_lines.sum do |line_item|
      line_item.duration_in_minutes.minutes.in_milliseconds.to_i
    end
    { total_ms: milliseconds }
  end
end
