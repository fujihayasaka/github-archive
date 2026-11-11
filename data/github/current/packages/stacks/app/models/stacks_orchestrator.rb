# typed: true
# frozen_string_literal: true

class StacksOrchestrator

  class ActiveRecordUpdateError < StandardError
    def initialize(message)
      super("Error while creating/updating orchestration active records : #{message}")
    end
  end

  def initialize(stack_instance_id, repo_id = nil, plan = nil, actor = nil)
    @stack_instance_id = stack_instance_id
    @repo_id = repo_id
    @plan = plan
    @actor = actor
    @error = nil
  end

  def run
    method_name = "#{self.class.name}##{__method__}"
    GitHub.tracer.in_span(method_name, kind: :internal) do
      GitHub::Logger.log(fn: method_name,
        message: "Feature disabled for current user",
        actor_id: @actor.id)
      push_orchestrator_metrics "status", "disabled"
    end
  end

  # Group steps by category (repo-cloning, config and workflow),
  # calculates overral status, start and end times of each step group
  def self.get_status(instance_id, plan_id = nil)
    plan = get_instance_plan(instance_id, plan_id)
    steps = plan.stacks_flow.map { |flow| plan.stacks_step.fetch_steps_for_flow(plan.instance_id, flow.id) }.flatten
    step_statuses = plan.stacks_flow.map { |flow| plan.stacks_status.fetch_step_status_records_for_flow(plan.instance_id, flow.id) }.flatten
    step_groups = steps.group_by { |step| step.get_step_group }
                       .sort_by { |key, _| key.order }

    status_groups = step_groups.map do |group, group_steps|
      step_group_status_records = step_statuses.select { |step_status| group_steps.map(&:id).include?(step_status.entity_id) }
      statuses = step_group_status_records.map { |step| StacksStatus.statuses[step.status] }
      error_messages = step_group_status_records&.select { |step| StacksStatus.statuses[step.status] == StacksStatus.statuses["failed"] }
                                    &.map { |step| [get_step_type(step.entity_id, group_steps), step.message] }.compact.to_h

      steps_metadata = group_steps.map { |step| step.get_step_metadata }

      StatusGroup.new(
        name: group.name,
        steps_metadata: steps_metadata,
        status: StacksStatus.statuses.key(compute_status(statuses)),
        start_time: group_steps.map { |step| step.start_time }.compact.min,
        end_time: group_steps.map { |step| step.end_time }.compact.max,
        messages: error_messages,
        total_jobs: group_steps.length
      )
    end
    overall_status = compute_status(status_groups.map { |group| StacksStatus.statuses[group.status] })
    failed_step_group = status_groups.find { |group| group.failed? }&.name

    StacksInstanceStatus.new(
      instance_id: instance_id,
      plan_id: plan.id,
      status: StacksStatus.statuses.key(overall_status),
      statuses: status_groups,
      failed_step_group: failed_step_group
    )
  end

  def self.get_step_type(id, steps)
    step = steps.select { |step| step.id == id }
    step&.first.type
  end

  def self.get_instance_plan(instance_id, plan_id)
    if plan_id.nil?
      # Get the latest plan
      plan_id = StacksPlan.where(instance_id: instance_id).order(:id).last&.id
    end

    StacksPlan.find(plan_id)
  end

  def self.compute_status(statuses)
    return StacksStatus.statuses[:not_started]  if statuses.empty?
    return StacksStatus.statuses[:success]      if success?(statuses)
    return StacksStatus.statuses[:failed]       if failed?(statuses)
    return StacksStatus.statuses[:in_progress]  if in_progress?(statuses)
    StacksStatus.statuses[:not_started]
  end

  def self.success?(statuses)
    statuses.all? { |status| status == StacksStatus.statuses[:success] }
  end

  def self.failed?(statuses)
    statuses.any? { |status| status == StacksStatus.statuses[:failed] }
  end

  def self.in_progress?(statuses)
    # combination of success and not_started is considered in progress
    in_progress_statuses = [StacksStatus.statuses[:success], StacksStatus.statuses[:not_started]]

    statuses.any? { |status| status == StacksStatus.statuses[:in_progress] } ||
      in_progress_statuses.all? { |status| statuses.include?(status) }
  end

  private_class_method :get_step_type, :get_instance_plan, :compute_status, :success?, :failed?, :in_progress?

  private

  def push_orchestrator_metrics(metric_name, status)
    Metrics.push_metric Metrics::INCREMENT, Component::ORCHESTRATOR, "run", metric_name, tags: ["action:#{status}"]
  end
end
