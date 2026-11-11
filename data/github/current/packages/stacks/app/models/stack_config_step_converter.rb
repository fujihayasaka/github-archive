# typed: true
# frozen_string_literal: true

require "yaml"
require "mustache"

class StackConfigStepConverter
  attr_accessor :stack_repo, :stack_repo_ref, :target_repo, :actor, :stack_schema_version, :input_hash
  def initialize(stack_repo, stack_repo_ref, target_repo, actor, stack_schema_version, input_hash)
    @stack_repo = stack_repo
    @stack_repo_ref = stack_repo_ref
    @target_repo = target_repo
    @actor = actor
    @stack_schema_version = stack_schema_version
    @input_hash = input_hash
  end

  STACK_CONFIG_STEP_MAPPING = YAML.safe_load(File.read(File.join(Rails.root, "packages/stacks/app/asset/stack_config_step_mapping.yaml")))

  def convert_yaml_to_steps(stack_yaml, user_public_key_id)
    steps_hash_list = []
    steps_hash_list.push(get_step_hash("repo-cloning", nil)) if stack_repo && target_repo && actor
    steps_hash_list.push(get_config_steps_hash_list(stack_yaml)) if stack_yaml["configs"].present?
    steps_hash_list.push(get_workflow_step_hash(stack_yaml)) if stack_yaml["init"].present?

    steps_hash_list.flatten.map do |step|
      StacksSteps::Step.new(type: "StacksSteps::#{step["name"]}", inputs: step["inputs"])
    end
  end

  private


  def get_config_steps_hash_list(stack_yaml)
    config_steps_details = stack_yaml["configs"]
    config_steps_details&.map do |key, steps_config|
      if steps_config.kind_of?(Array)
        steps_config.map { |step| get_step_hash(key, step) }
      else
        get_step_hash(key, steps_config)
      end
    end
  end

  def get_workflow_step_hash(stack_yaml)
    workflow_step_details = stack_yaml["init"]
    merged_inputs_hash = merge_stack_and_user_inputs(stack_yaml["inputs"], input_hash)
    get_step_hash("init", workflow_step_details, merged_inputs_hash)
  end

  def merge_stack_and_user_inputs(stack_inputs, user_inputs)
    # intersection of stack inputs and provided inputs
    stack_inputs_hash = {}
    user_inputs["inputs"].each do |key, val|
      input = stack_inputs.find { |input| input["name"] == key }
      stack_inputs_hash[key] = { "value" => val, "is-secret" => input["is-secret"] } if input.present?
    end
    stack_inputs_hash
  end

  def get_step_hash(config_name, config, stack_inputs_hash = {})
    step_template_yaml = get_mapping(config_name)
    return {} unless step_template_yaml.present?
    step_yaml = StacksMustache.render(step_template_yaml,
      {
        "config" => config,
        "stack_repo" => stack_repo,
        "ref" => stack_repo_ref,
        "target_repo" => target_repo,
        "actor" => actor,
        "stack_inputs_hash" => stack_inputs_hash
      })
    step_yaml.present? ? YAML.safe_load(step_yaml) : {}
  end

  def get_mapping(config_name)
    STACK_CONFIG_STEP_MAPPING[stack_schema_version][config_name]
  end

  def push_step_validate_metrics(status, step_name)
    Metrics.push_metric Metrics::INCREMENT, Component::STEP, "input", "validation", tags: ["action:#{status}", "step:#{step_name}"]
  end
end
