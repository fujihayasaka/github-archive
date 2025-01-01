# typed: true
# frozen_string_literal: true

require_relative "yaml_parsing/memory_helper"
require_relative "yaml_parsing/safe_yaml_parser"
require_relative "yaml_parsing/diff_helper"

class Actions::ParsedWorkflow
  WORKFLOW_DISPATCH = "workflow_dispatch"
  WORKFLOW_CALL = "workflow_call"
  SCHEDULE = "schedule"

  INPUT_TYPE_TEXT = "text"
  INPUT_TYPE_CHOICE = "choice"
  INPUT_TYPE_ENVIRONMENT = "environment"
  INPUT_TYPE_BOOLEAN = "boolean"
  INPUT_TYPE_NUMBER = "number"

  attr_reader :file_size

  def self.parse_from_yaml(repository, path, branch = nil, sha = nil)
    return nil unless repository
    return nil if path.empty?

    # Logging fields for tracing
    logging_fields = {
      "code.namespace" => self.name,
      "gh.repo.id" => repository.id,
      "gh.repo.global_id" => repository.global_relay_id,
      "gh.repo.public" => repository.public?,
    }
    if repository.public?
      logging_fields["gh.repo.nwo"] = repository.name_with_display_owner
      logging_fields["gh.workflow.path"] = path
      if sha
        logging_fields["gh.repo.ref"] = sha
      else
        logging_fields["gh.repo.ref"] = branch || repository.default_branch
      end
    end

    workflow_file = if sha
      repository.workflow_content_by_sha(repository, sha, path)
    else
      repository.workflow_content(repository, branch || repository.default_branch, path)
    end
    return nil unless workflow_file && workflow_file.data
    return nil if workflow_file.binary?

    content = GitHub::Encoding.strip_bom(workflow_file.data.to_s)

    # Choose which parser to use based on feature flags
    if use_new_yaml_parser_cutover?(repository)
      file_data, _ = parse_yaml_with_new_parser(content, logging_fields)
    elsif use_new_yaml_parser_tracing?(repository)
      file_data, _ = parse_yaml_with_tracing(content, logging_fields)
    else
      file_data, _ = parse_yaml_with_legacy_parser(content, logging_fields)
    end

    file_data = {} unless file_data.is_a?(Hash)

    Actions::ParsedWorkflow.new(repository: repository, path: path, file_size: workflow_file.size, data: file_data)
  end

  # Parses YAML using the legacy parser
  # @param content [String] The YAML content to parse
  # @param logging_fields [Hash] Logging fields
  # @return [Array] The parsed YAML content and any user error encountered
  def self.parse_yaml_with_legacy_parser(content, logging_fields)
    begin
      [YAML.safe_load(content, permitted_classes: [Date, Time, Symbol]), nil]
    rescue Psych::Exception => e
      GitHub.logger.info(
        "User error when parsing YAML using legacy parser",
        "code.function" => __method__,
        "gh.actions.yaml_parser.user_error.class" => e.class,
        "gh.actions.yaml_parser.user_error.message" => e.message,
        **logging_fields,
      )
      [nil, e]
    rescue => e
      GitHub.logger.info(
        "Unexpected error when parsing YAML using legacy parser",
        "code.function" => __method__,
        "gh.actions.yaml_parser.unexpected_error.class" => e.class,
        "gh.actions.yaml_parser.unexpected_error.message" => e.message,
        **logging_fields,
      )
      GitHub.dogstats.increment("actions.parsed_workflow.legacy_yaml_parser.unexpected_error")
      raise e
    end
  end

  # Parses YAML using the new parser
  # @param content [String] The YAML content to parse
  # @param logging_fields [Hash] Logging fields
  # @return [Array] The parsed YAML content and any user error encountered
  def self.parse_yaml_with_new_parser(content, logging_fields)
    begin
      # Memory-safe YAML parser with anchor support
      result = Actions::YamlParsing::SafeYamlParser.safe_load(
        content,
        max_bytes: Actions::YamlParsing::SafeYamlParser::DEFAULT_MAX_BYTES,
        max_depth: Actions::YamlParsing::SafeYamlParser::DEFAULT_MAX_DEPTH,
        max_nodes_traversed: Actions::YamlParsing::SafeYamlParser::DEFAULT_MAX_NODES_TRAVERSED
      )
      [result, nil]
    rescue Actions::YamlParsing::UserError => e
      GitHub.logger.info(
        "User error when parsing YAML",
        "code.function" => __method__,
        "gh.actions.yaml_parser.user_error.class" => e.class,
        "gh.actions.yaml_parser.user_error.message" => e.message,
        **logging_fields,
      )
      [nil, e]
    rescue => e
      GitHub.dogstats.increment("actions.parsed_workflow.yaml_parser.error")
      # TODO: Switch this to .error() after confirm stability
      GitHub.logger.info(
        "Unexpected error when parsing YAML",
        "code.function" => __method__,
        "gh.actions.yaml_parser.unexpected_error.class" => e.class,
        "gh.actions.yaml_parser.unexpected_error.message" => e.message,
        **logging_fields,
      )
      raise e
    end
  end

  # Parses YAML using the legacy parser and compares with the new parser
  # @param content [String] The YAML content to parse
  # @param logging_fields [Hash] Logging fields
  # @return [Array] The parsed YAML content and any user error encountered
  def self.parse_yaml_with_tracing(content, logging_fields)
    # Legacy parser
    existing_result, existing_user_error = parse_yaml_with_legacy_parser(content, logging_fields)

    # New parser
    begin
      new_result, new_user_error = parse_yaml_with_new_parser(content, logging_fields)
    rescue
      # Skip compare
      # Note, unexpected exceptions are logged already by parse_yaml_with_new_parser
      return [existing_result, existing_user_error]
    end

    # Compare
    begin
      diff_description = Actions::YamlParsing::DiffHelper.compare(
        existing_user_error.nil? ? existing_result : existing_user_error,
        new_user_error.nil? ? new_result : new_user_error
      )
      if diff_description
        GitHub.logger.info(
          "YAML parser difference",
          "code.function" => __method__,
          "gh.actions.yaml_parser.diff_description" => diff_description,
          **logging_fields,
        )
      end
    rescue => e
      GitHub.dogstats.increment("actions.parsed_workflow.tracing_comparison_error")
      GitHub.logger.info(
        "YAML parser diff error",
        "code.function" => __method__,
        "gh.actions.yaml_parser.diff_error.class" => e.class,
        "gh.actions.yaml_parser.diff_error.message" => e.message,
        **logging_fields,
    )
    end

    [existing_result, existing_user_error]
  end

  def self.use_new_yaml_parser_tracing?(repository)
    GitHub.flipper[:actions_new_yaml_parser_tracing].enabled?(repository.owner)
  end

  def self.use_new_yaml_parser_cutover?(repository)
    GitHub.flipper[:actions_new_yaml_parser_cutover].enabled?(repository.owner)
  end

  def initialize(repository:, path:, file_size:, data:)
    @repository = repository
    @path = path
    @file_size = file_size
    @data = data
  end

  def name
    @data["name"] || @path
  end

  def has_workflow_dispatch_trigger?
    triggers.key?(WORKFLOW_DISPATCH)
  end

  def has_schedule_trigger?
    triggers.key?(SCHEDULE)
  end

  def has_workflow_call_trigger?
    triggers.key?(WORKFLOW_CALL)
  end

  def valid_hash?
    @data != {}
  end

  def workflow_dispatch_inputs
    return nil unless has_workflow_dispatch_trigger?

    trigger = triggers[WORKFLOW_DISPATCH]
    return nil unless trigger

    inputs = trigger["inputs"]
    return nil unless inputs && inputs.is_a?(Hash)

    result = {}

    inputs.each do |key, value|
      # If value is defined, we expect it to be a map in yaml/hash
      return nil if value && !value.is_a?(Hash)

      # None of the values are required, provide a default for each one if it's not set
      boolean_type_false_default = value && (value["default"] == false || (value["type"] == "boolean" && (value["required"] == false || value["required"].nil?))) && "false"
      number_type = value && value["type"] == "number" && number_type_supported
      number_type_default = number_type && ((value["default"] && ((value["default"].is_a?(Numeric) && value["default"]) || 0)) || (value["required"] == false || value["required"].nil?) && 0)
      result[key] = {
        description: value && value["description"] || "",
        required: !!(value && value["required"]),
        default: number_type_default || (value && value["default"] || boolean_type_false_default || "").to_s,
      }.tap do |result|
        type = value && value["type"] || INPUT_TYPE_TEXT
        result[:type] = type
        # Force all values to be strings
        result[:options] = (value && value["options"])&.map(&:to_s) || [] if type == INPUT_TYPE_CHOICE
      end
    end

    result
  end

  def process_inputs(provided_inputs)
    provided_inputs = provided_inputs || {}
    expected_inputs = workflow_dispatch_inputs || {}

    return nil if provided_inputs.empty? && expected_inputs.empty?

    unexpected_inputs = provided_inputs.keys - expected_inputs.keys
    if unexpected_inputs.present?
      raise ArgumentError, "Unexpected inputs provided: #{unexpected_inputs}"
    end

    input_values = {}

    expected_inputs.each do |key, input|
      if input[:type] == "number" && number_type_supported && !provided_inputs[key].nil?
        number = Float(provided_inputs[key]) rescue nil
        raise ArgumentError, "Provided value '#{provided_inputs[key]}' for input '#{key}' is not a number" unless number.present?
        input_values[key] = number
      elsif input[:type] == "boolean" && [true, false].include?(provided_inputs[key])
        input_values[key] = provided_inputs[key].to_s
      elsif provided_inputs[key].present?
        raise ArgumentError, "Invalid value for input '#{key}'" unless provided_inputs[key].is_a?(String)
        input_values[key] = provided_inputs[key]
      elsif input[:default].present?
        input_values[key] = input[:default]
      elsif input[:required]
        raise ArgumentError, "Required input '#{key}' not provided"
      end

      value = input_values[key]

      # Skip validation when the value is nil for a non required input
      next if value.nil?

      case input[:type]
      when INPUT_TYPE_CHOICE
        options = input[:options]
        unless options.include? value
          raise ArgumentError, "Provided value '#{value}' for input '#{key}' not in the list of allowed values"
        end
      when INPUT_TYPE_BOOLEAN
        unless %w[true false].include? value
          raise ArgumentError, "Provided value '#{value}' for input '#{key}' not in the list of allowed values"
        end
      when INPUT_TYPE_ENVIRONMENT
        unless @repository.environments.exists?(name: value)
          raise ArgumentError, "Provided environment '#{value}' does not exist in the repository"
        end
      end
    end

    input_values
  end

  def number_type_supported
    return @number_type_supported if defined?(@number_type_supported)

    @number_type_supported = GitHub.flipper[:actions_number_type_dispatch_inputs].enabled?(@repository.owner)
  end

  # Returns the names of the events that trigger this workflow.
  # Not limited to webhook events.
  sig { returns(T::Array[String]) }
  def trigger_events
    triggers.keys
  end

  def schedule
    triggers.fetch(SCHEDULE, nil)
  end

  def except_schedule
    triggers.except(SCHEDULE)
  end

  # Pulls out the referenced actions in the current workflow file
  def referenced_actions
    return [] unless @data["jobs"] && @data["jobs"].keys.any?

    jobs = @data["jobs"].keys.map { |name| @data["jobs"][name] }
    return [] unless jobs && jobs.any?

    referenced_actions = []
    jobs.each do |job|
      next unless job && job["steps"] && job["steps"].any?
      job["steps"].each do |step|
        next unless step && step["uses"]
        referenced_actions << step["uses"]
      end
    end

    referenced_actions
  end

  private

  def triggers
    @triggers ||= begin
      # Psych parses "on:" as true if it's not quoted as per the YAML 1.1 spec.
      triggers = @data[true] || @data["on"]
      if triggers.is_a?(Array)
        return triggers.map { |x| [x, {}] }.to_h
      elsif triggers.is_a?(Hash)
        return triggers
      elsif triggers.is_a?(String)
        return { triggers => {} }
      end

      {}
    end
  end
end
