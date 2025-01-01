# typed: false
# frozen_string_literal: true

class StackPlanner
  include StacksSteps
  DEFAULT_SCHEMA_VERSION = "0.1.0"
  WEIGHT_THRESHOLD = 180

  attr_accessor :instance_id, :stack_template_yaml, :stack_repo, :stack_repo_ref, :target_repo, :actor, :input_hash, :user_public_key_id, :is_retry_plan

  def initialize(instance_id, stack_template_yaml, stack_repo, stack_repo_ref, target_repo, actor, input_hash, user_public_key_id, is_retry_plan)
    @instance_id = instance_id
    @stack_template_yaml = stack_template_yaml
    @stack_repo = stack_repo
    @stack_repo_ref = stack_repo_ref
    @target_repo = target_repo
    @actor = actor
    @input_hash = input_hash
    @user_public_key_id = user_public_key_id
    @is_retry_plan = is_retry_plan
  end

  def create_plan
    stack_yaml = YAML.safe_load(stack_template_yaml)
    schema_version = stack_yaml["stack_schema_version"].present? ? stack_yaml["stack_schema_version"] : StackParser::DEFAULT_SCHEMA_VERSION
    step_converter = StackConfigStepConverter.new(stack_repo, stack_repo_ref, target_repo, actor, schema_version, input_hash)
    steps = step_converter.convert_yaml_to_steps(stack_yaml, user_public_key_id)
    prepare_plan(steps)
  end

  private

  def prepare_plan(steps)
    sorted_steps = sort(steps)
    add_cleanup_step(sorted_steps) if is_retry_plan
    validate_steps(sorted_steps)
    plan = StacksPlan.new(instance_id: instance_id, actor_id: actor.id)
    current_weight, current_flow = 0, nil

    sorted_steps.each do |step|
      raise Errors::StepInvalidWeightError.new(step["name"]) if weight_threshold_reached?(step.weight)
      if weight_threshold_reached?(current_weight + step.weight) || current_flow.nil?
        flow = StacksFlow.new(instance_id: instance_id, plan: plan, depends_on: current_flow)
        plan.stacks_flow.append(flow)
        current_flow, current_weight = flow, 0
      end
      step.instance_id, step.plan, step.flow = instance_id, plan, current_flow
      current_weight = current_weight + step.weight
      current_flow.stacks_step.append(step)
    end

    plan
  end

  def validate_steps(steps)
    GitHub.tracer.in_span("StackSteps#validate_inputs", kind: :internal) do |span|
      steps.each do |step|
        step.class.validate_inputs(step.inputs, repo: target_repo, actor: actor, stack_repo: stack_repo)
        push_step_validate_metrics "success", step["name"]
      rescue StandardError => exception # rubocop:todo Lint/RescueException
        push_step_validate_metrics "error", step["name"]
        span.add_event("exception", attributes: { "exception.type" => exception.class.name })
        raise exception
      end
    end
  end

  def sort(steps)
    sorted_steps = steps.select { |step| step.class.get_step_name == RepoMetadataStep.get_step_name }
    sorted_steps << steps.reject { |step| sorted_steps.include?(step) }
    sorted_steps.flatten.group_by { |step| step.get_step_group }
                .sort_by { |key, _| key.order }
                .map { |_, value| value }.flatten
  end

  def add_cleanup_step(steps)
    cleanup_step = StacksSteps::Step.new(type: "StacksSteps::#{CleanupStep.get_step_name}", inputs: input_hash)
    steps.insert(0, cleanup_step)
  end

  def weight_threshold_reached?(weight)
    weight > WEIGHT_THRESHOLD
  end

  def push_step_validate_metrics(status, step_name)
    Metrics.push_metric Metrics::INCREMENT, Component::STEP, "input", "validation", tags: ["action:#{status}", "step:#{step_name}"]
  end
end
