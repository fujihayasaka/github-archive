# typed: false
# frozen_string_literal: true

require "json"
require "json_schema"

class StackParser
  ONE_KB = 1024
  TEN_KB = ONE_KB * 10
  HUNDRED_KB = ONE_KB * 100
  DEFAULT_SCHEMA_VERSION = "0.1.0"
  SCHEMA_NONEXISTENT = "invalid schema version"

  VALIDATION_FAILED = "validation failed"

  STACK_TEMPLATE = "StackTemplate"
  STACK_TEMPLATE_VALUES = "StackTemplateValues"

  STACK_TEMPLATE_FILE_PATH = ".github/stacks/stack.%s"
  STACK_TEMPLATE_VALUES_PATH = ".github/stacks/values.%s"

  SCHEMAS = {
    "0.1.0" => JSON.parse(File.read(File.join(Rails.root, "packages/stacks/app/asset/stack_schema-0.1.0.json")))
  }.freeze

  attr_reader :stack_schema, :stack_template, :stack_template_obj, :values, :stack_template_path

  @stack_repo = nil
  @stack_repo_ref = nil
  @target_oid = nil
  @stack_template = nil
  @stack_template_obj = nil
  @stack_schema = nil

  def initialize(stack_repo, stack_repo_ref = nil, target_oid = nil)
    @stack_repo = stack_repo
    if target_oid
      @target_oid = target_oid
    elsif stack_repo_ref
      @stack_repo_ref = stack_repo_ref
      @target_oid = stack_repo_ref.target_oid
    else
      @stack_repo_ref = @stack_repo.refs.find(@stack_repo.default_branch.b)
      @target_oid = @stack_repo_ref.target_oid
    end

    @stack_template, @stack_template_obj = get_validated_stack_template
    @values = get_validated_values_yaml_obj

    schema_version = @stack_template_obj.fetch("stack_schema_version", DEFAULT_SCHEMA_VERSION)
    raise Errors::StacksParserError.new("Initialization failed.", SCHEMA_NONEXISTENT) unless (@stack_schema = SCHEMAS[schema_version])
  end

  def get_stack_inputs
    @stack_template_obj["inputs"]
  end

  def get_stack_env_name_inputs
    env_obj = @stack_template_obj.dig("configs", "environments")
    env_name_inputs = env_obj.present? ? env_obj.select { |e| e["name"].match /\${{\s*inputs\.[-\w\.]+\s*}}/ }.map { |e| e["name"] } : []
  end

  def get_stack_github_apps
    @stack_template_obj["github-apps"]
  end

  def get_stack_metadata
    @stack_template_obj.slice("name", "description", "branding")
  end

  def parse_and_get_plan(instance_id, target_repo, actor, inputs = {}, user_public_key_id = nil, is_retry_plan = false)
    GitHub.tracer.in_span("#{self.class.name}##{__method__}", kind: :internal) do |span|
      span.add_attributes("actor_id" => actor.id, "stack_repo_id" => @stack_repo.id, "target_repo_id" => target_repo.id)
      values_yaml_obj = get_validated_values_yaml_obj

      validate_inputs(inputs)
      input_hash = merge_input_values(values_yaml_obj, inputs)

      evaluated_stack_template = StacksMustache.render(@stack_template, input_hash)

      begin
        StackParser.validate_schema(YAML.safe_load(evaluated_stack_template), @stack_schema)
      rescue JsonSchema::SchemaError, JsonSchema::AggregateError => error
        push_parser_execution_status_metrics "validation", "schema", "error"
        raise Errors::StacksParserError.new("StackSchemaValidator", VALIDATION_FAILED)
      end

      plan = nil
      elapsed_time = Benchmark.realtime do
        stack_planner = StackPlanner.new(instance_id, evaluated_stack_template, @stack_repo, @stack_repo_ref, target_repo, actor, input_hash, user_public_key_id, is_retry_plan)
        plan = stack_planner.create_plan
      end
      elapsed_time_ms = (elapsed_time * 1000).round
      Metrics.push_metric Metrics::DISTRIBUTION, Component::PARSER, "create_plan", "time", value: elapsed_time_ms

      plan
    end
  end

  def self.validate_schema(stack_template_obj, schema, fail_fast = true)
    schema = JsonSchema.parse!(schema)
    schema.expand_references!
    schema.validate!(stack_template_obj, fail_fast: fail_fast)
  end

  private

  def merge_input_values(values_yaml_obj, inputs)
    if !values_yaml_obj.nil?
      values_yaml_obj["inputs"].merge!(inputs)
    else
      values_yaml_obj = { "inputs" => inputs }
    end

    values_yaml_obj
  end

  def get_validated_stack_template
    stack_template_blob = read_yaml(STACK_TEMPLATE_FILE_PATH)
    if stack_template_blob.nil?
      push_parser_execution_status_metrics "validation", "template", "error"
      raise Errors::StacksParserError.new(STACK_TEMPLATE, VALIDATION_FAILED)
    end

    # Check stack_template file size
    if stack_template_blob.size > HUNDRED_KB
      push_parser_execution_status_metrics "validation", "template", "error"
      raise Errors::StacksParserError.new(STACK_TEMPLATE, VALIDATION_FAILED)
    end

    stack_template = stack_template_blob.data
    if stack_template.nil?     # It can be binary or invalid encoding as per app/models/blob.rb
      push_parser_execution_status_metrics "validation", "template", "error"
      raise Errors::StacksParserError.new(STACK_TEMPLATE, VALIDATION_FAILED)
    end

    begin
      stack_template_obj = YAML.safe_load(stack_template)
    rescue Psych::Exception
      push_parser_execution_status_metrics "validation", "template", "error"
      raise Errors::StacksParserError.new(STACK_TEMPLATE, "Stack YAML load error")
    end

    @stack_template_path = stack_template_blob.path

    push_parser_execution_status_metrics "validation", "template", "success"

    [sanitise_yaml_file(stack_template), stack_template_obj]
  end

  def get_validated_values_yaml_obj
    value_file_blob = read_yaml(STACK_TEMPLATE_VALUES_PATH)

    return nil if value_file_blob.nil?

    # Check stack_template file size
    if value_file_blob.size > TEN_KB
      push_parser_execution_status_metrics "validation", "values", "error"
      raise Errors::StacksParserError.new(STACK_TEMPLATE_VALUES, VALIDATION_FAILED)
    end

    values_yaml = value_file_blob.data
    if values_yaml.nil?     # It can be binary or invalid encoding as per app/models/blob.rb
      push_parser_execution_status_metrics "validation", "values", "error"
      raise Errors::StacksParserError.new(STACK_TEMPLATE_VALUES, VALIDATION_FAILED)
    end

    if !is_user_input_safe(values_yaml)
      push_parser_execution_status_metrics "validation", "values", "error"
      raise Errors::StacksParserError.new(STACK_TEMPLATE_VALUES, VALIDATION_FAILED)
    end

    begin
      values_obj = YAML.safe_load(values_yaml)
    rescue Psych::Exception
      push_parser_execution_status_metrics "validation", "values", "error"
      raise Errors::StacksParserError.new(STACK_TEMPLATE, "Values YAML load error")
    end

    push_parser_execution_status_metrics "validation", "values", "success"

    values_obj
  end

  def read_yaml(file_name)
    file_path = file_name % ["yml"]
    file_yml = @stack_repo.blob(@target_oid, file_path)

    file_path = file_name % ["yaml"]
    file_yaml = @stack_repo.blob(@target_oid, file_path)

    file_yml or file_yaml
  end

  def validate_inputs(inputs_hash)
    inputs_hash.each do |_key, value|
      if !is_user_input_safe(value)
        raise Errors::StacksParserError.new("Input", VALIDATION_FAILED)
      end
    end
  end

  def is_user_input_safe(text)
    !text.kind_of?(String) || text.index(/{}/).nil?  # values yaml file shouldn't contain any mustache expression
  end

  def sanitise_yaml_file(yaml_string)
    uncommented_string = String.new
    yaml_string.gsub!(/\r\n?/, "\n")
    re = Regexp.new(/[#]/)
    yaml_string.each_line do |line|
      if index = (line =~ re)
        if index > 0
          uncommented_string.concat(line[0, index].rstrip, "\n")     # slice the string where the regular expression matches, and return it.
        end
      else
        uncommented_string.concat(line.rstrip, "\n")
      end
    end
    uncommented_string
  end

  def push_parser_execution_status_metrics(operation, metric_name, status)
    Metrics.push_metric Metrics::INCREMENT, Component::PARSER, operation, metric_name, tags: ["action:#{status}"]
  end
end
