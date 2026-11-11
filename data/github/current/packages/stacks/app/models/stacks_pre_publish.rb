# typed: true
# frozen_string_literal: true

# Making any changes to the validations here?
# You would have to add these validations in app/assets/modules/github/editor/yaml-editors/stack-template/stack-template-rules.ts

class StacksPrePublish
  WRONG_TYPE_ERROR = "Wrong type received"
  VALUES_MATCH_ERROR = "values.yml value doesn't match input type"
  INPUT_MULTIPLE_DECLARATION_ERROR = "Input has multiple declarations"
  INPUT_WHITESPACE_ERROR = "Input has whitespace"
  INPUT_LENGTH_ERROR = "Input longer than 1024 characters"
  VALID_VALUES_MATCH_ERROR = "Valid value type doesn't match input type"
  DEFAULT_VALUE_MATCH_ERROR = "Default value type doesn't match input type"
  UNDEFINED_INPUT_ERROR = "Undefined input referenced"
  INCONSISTENT_REFERENCE_ERROR = "Input referenced in multiple places with different types expected"
  INVALID_SLUG_ERROR = "Invalid slug provided"
  APP_LIMIT_EXCEEDED = "App limit of 100 exceeded"

  def initialize(stack_repo, target_oid = stack_repo.refs.find(stack_repo.default_branch.b).target_oid)
    @target_oid = target_oid
    stack_parser = StackParser.new(stack_repo, nil, @target_oid)

    @stack_repo = stack_repo
    raise Errors::StacksPrePublishErrors.new("Stack associated to repository not found", {}) unless @stack = @stack_repo.stack

    @errors = []
    @inputs_defined = stack_parser.get_stack_inputs || []
    @values = (stack_parser.values || {}).fetch("inputs", {})
    @stack_template = stack_parser.stack_template
    @stack_schema = stack_parser.stack_schema
    @stack_template_obj = stack_parser.stack_template_obj
    @template_path = stack_parser.stack_template_path
    @stack_readme = @stack.readme(committish: @target_oid)
  end

  def self.validate(stack_repo, target_oid = nil)
    begin
      new(stack_repo, target_oid).validate
    rescue Errors::StacksParserError
      {
        template_exists: false
      }
    rescue Errors::StacksPrePublishErrors
      {
        template_exists: true,
        branding: false,
        template: false,
        readme: false,
        template_path: false,
      }
    end
  end

  def validate
    result = {
      template_exists: true,
      branding: validate_branding,
      template: validate_template,
      init: validate_init,
      init_section_exists: @init_section_exists,
      init_exists: @workflow_exists,
      readme: validate_readme,
      template_path: @template_path,
    }
    result[:readme_path] = @stack_readme.path if @stack_readme.present?
    result[:init_path] = ".github/workflows/#{(@stack_template_obj["init"] || {})["uses"]}" if (init_path = (@stack_template_obj["init"] || {})["uses"]) && !is_input_reference?(init_path)

    result
  end

  # stack init checks
  def validate_init
    @workflow_exists = false
    @init_section_exists = false
    return [] if !(init_path = (@stack_template_obj["init"] || {})["uses"]) || is_input_reference?(init_path)

    @init_section_exists = true
    @workflow_path = (@stack_template_obj["init"] || {})["uses"]
    begin
      workflow_file = @stack_repo.tree_entry(@target_oid, ".github/workflows/#{init_path}")
    rescue GitRPC::Error
      return ["#{init_path} not found."]
    end

    @workflow_exists = true

    return ["Could not read workflow file."] unless workflow_file && workflow_file.data
    return ["Invalid workflow."] if workflow_file.binary?

    begin
      content = GitHub::Encoding.strip_bom(workflow_file.data.to_s)
      file_data = YAML.safe_load(content, permitted_classes: [Date, Time])
    rescue Psych::Exception
      file_data = {}
    end

    file_data = {} unless file_data.is_a?(Hash)

    parsed_workflow = Actions::ParsedWorkflow.new(repository: @stack_repo, path: ".github/workflows/#{init_path}", file_size: workflow_file.size, data: file_data)

    (["workflow_dispatch trigger not found in #{init_path}"] unless parsed_workflow.has_workflow_dispatch_trigger?) || []
  end

  # readme checks
  def validate_readme
    @stack_readme.present? ? [] : ["Readme missing."]
  end

  # branding checks
  def validate_branding
    errors = []

    errors.concat(name_errors)
    errors.concat(description_errors)
    errors.concat(branding_errors)
  end

  # template checks
  def validate_template
    errors = (["Issues found in stack.yml."] if !template_valid? || !configs_errors.empty?) || []
    errors.concat(app_section_errors)
  end

  private

  # config validations
  def configs_errors
    errors = []

    errors.concat(branches_errors)
    errors.concat(repo_metadata_errors)
    errors.concat(environment_errors)
    errors.concat(security_errors)
  end

  def branches_errors
    errors = []

    branches_names = Set.new

    (@stack_template_obj.dig("configs", "branches") || []).each_with_index do |branch_config, index|
      errors.append("#{branch_config["name"]} is a repeated name.") if branches_names.include?(branch_config["name"])
      branches_names.add(branch_config["name"])

      errors.append("required-approving-review-count for #{index} branch config should be between 0 - #{ProtectedBranch::MAX_REQUIRED_APPROVING_REVIEW_COUNT}") if !is_input_reference?((count = branch_config.dig("parameters", "required-pull-request-reviews", "required-approving-review-count"))) && ConfigValidations::out_of_range?(count, 0, ProtectedBranch::MAX_REQUIRED_APPROVING_REVIEW_COUNT)
    end

    errors
  end

  def repo_metadata_errors
    errors = []

    topics = (@stack_template_obj.dig("configs", "repo-metadata", "parameters", "topics") || [])
    errors.append("Max of #{RepositoryTopic::LIMIT_PER_REPOSITORY} allowed.") if ConfigValidations::length_out_of_range?(topics, 1, RepositoryTopic::LIMIT_PER_REPOSITORY)
    topics.each do |topic|
      errors.append("#{topic} is invalid.") if !is_input_reference?(topic) && !Topic.valid_name?(topic)
    end

    errors
  end

  def environment_errors
    errors = []

    environment_names = Set.new

    (@stack_template_obj.dig("configs", "environments") || []).each_with_index do |env_config, index|
      errors.append("#{env_config["name"]} is a repeated name.") if environment_names.include?(env_config["name"])
      environment_names.add(env_config["name"])

      errors.append("Names should not be longer that 255") if !is_input_reference?(env_config["name"]) && ConfigValidations::length_out_of_range?(env_config["name"], 1, 255)
      errors.append("protected-branches and allowed-branch-rules cannot be set at the same time for environment #{env_config["name"]}") if ConfigValidations::environment_branch_invalid?(env_config.dig("parameters") || {})
      errors.append("Maximum of #{Gate::MAX_APPROVERS} reviewers can be given for an environment.") if ConfigValidations::length_out_of_range?(env_config.dig("parameters", "reviewers"), 1, Gate::MAX_APPROVERS)
      errors.append("wait-timer for #{index} config should be between 0 - #{Gate::MAX_TIMEOUT_MINUTES}") if !is_input_reference?(count = env_config.dig("parameters", "wait-timer")) && ConfigValidations::out_of_range?(count, 0, Gate::MAX_TIMEOUT_MINUTES)
    end

    (@stack_template_obj["github-apps"] || []).each do |app_config|
      errors.append("Invalid environment referenced for #{app_config["slug"]}") if (env_name = app_config.dig("parameters", "environment")).present? && !is_input_reference?(env_name) && !environment_names.include?(app_config.dig("parameters", "environment"))
    end

    errors
  end

  def security_errors
    (["vulnerability-alerts needs to be enabled for automated-security-fixes"] if @stack_template_obj.dig("configs", "security", "parameters", "automated-security-fixes").equal?(true) && ((vul_alerts = @stack_template_obj.dig("configs", "security", "parameters", "vulnerability-alerts")).nil? || vul_alerts.equal?(false))) || []
  end

  def app_section_errors
    return [] unless @stack_template_obj["github-apps"]

    apps = @stack_template_obj["github-apps"]

    errors = []

    errors.append("Maximum of 100 apps can be defined.") if apps.length > 100

    app_slugs = apps.map { |app_config| app_config["slug"] }.filter { |app_slug| !is_input_reference?(app_slug) }
    existing_apps = Integration.where(slug: app_slugs)
    existings_apps_slugs = existing_apps.map { |app| app.slug }

    errors.concat((app_slugs - existings_apps_slugs).map { |app_slug| "App slug #{app_slug} is invalid." })

    errors
  end

  # pre publish run
  def template_valid?
    begin
      validate_template_config.empty?
    rescue Errors::StacksParserError, Errors::StacksPrePublishErrors => e
      false
    end
  end

  def validate_template_config
    # returns with set of inputs whose type couldn't be figured out
    inputs_without_value, inputs_set = inputs_without_values

    # if a set has been returned then there are inputs whose types need to be figured out from the configs
    populate_inputs_without_values(inputs_without_value, inputs_set) if @errors.empty? && inputs_without_value.kind_of?(Set)

    begin
      # validate with the stack schema after substituting the values
      StackParser.validate_schema(
        YAML.safe_load(StacksMustache.render(@stack_template, { "inputs" => @values })),
        @stack_schema,
        false
      ) if @errors.empty?
    rescue JsonSchema::AggregateError => schema_errors
      @errors.concat schema_errors.errors
    rescue JsonSchema::SchemaError => schema_error
      @errors.concat schema_error.message
    end

    @errors
  end

  # metadata validation
  def branding_errors
    return ["No branding found in #{@stack.stack_file_name}"] if @stack_template_obj["branding"].nil?
    icon_errors + color_errors
  end

  def icon_errors
    template_icon_name_value = @stack_template_obj.dig("branding", "icon")
    return ["Icon missing in branding."] if template_icon_name_value.nil?
    (["Invalid icon in branding."] unless RepositoryActions::Icons::NAMES.include?(template_icon_name_value.downcase)) || []
  end

  def color_errors
    template_color_value = @stack_template_obj.dig("branding", "color")
    return ["Color missing in branding."] if template_color_value.nil?
    (["Invalid color in branding."] unless RepositoryActions::Colors.select_by_name_or_hex(template_color_value).present?) || []
  end

  def name_errors
    name_value = @stack_template_obj["name"]
    return ["Name missing."] if name_value.nil?
    return ["Name cannot be an input reference."] if is_input_reference?(name_value)

    @stack.name = name_value
    @stack.set_slug
    @stack.validate

    (["Name must be unique. Cannot match an existing Stack name."] unless @stack.errors[:name].empty? && @stack.errors[:slug].empty?) || []
  end

  def description_errors
    description_value = @stack_template_obj["description"]
    return ["Description missing."] if description_value.nil?
    return ["Description cannot be an input reference."] if is_input_reference?(description_value)

    @stack.description = description_value
    # Simulate the Stack being listed because description validations are more strict
    @stack.state = "listed"
    @stack.validate

    (["Add a sentence describing your Stack in 125 characters or less"] unless @stack.errors[:description].empty?) || []
  end

  def is_input_reference?(value)
    value.class == String && value.strip.start_with?("${{") && value.end_with?("}}")
  end

  def populate_inputs_without_values(inputs_without_value, inputs_set)
    input_references_with_type = {}

    # parses through the sections trying to find out input references and the type expected
    populate_input_references_with_type(@stack_template_obj, @stack_schema, input_references_with_type)

    input_references_with_type.each do |input_reference, type|
      # append error if input not defined in inputs section is referred
      @errors.append(Errors::StacksPrePublishErrors.new(UNDEFINED_INPUT_ERROR, { "input" => input_reference })) if !inputs_set.include? input_reference

      # assign default value based on type inferred from configs
      @values[input_reference] = default_value_for_type(type) if inputs_without_value.include? input_reference
    end
  end

  def inputs_without_values
    # validate if inputs are defined as per schema
    begin
      StackParser.validate_schema(@inputs_defined, schema_for(@stack_schema, ["inputs"]), false)
    rescue JsonSchema::AggregateError => schema_errors
      @errors.concat schema_errors.errors
    rescue JsonSchema::SchemaError => schema_error
      @errors.concat schema_error.message
    end

    return @errors unless @errors.empty?

    inputs_set = Set.new
    inputs_without_value = Set.new

    @inputs_defined.each do |input|
      value = nil

      if inputs_set.include? input["name"]
        @errors.append(Errors::StacksPrePublishErrors.new(INPUT_MULTIPLE_DECLARATION_ERROR, { "input" => input["name"] }))
      else
        inputs_set << input["name"]

        @errors.append(Errors::StacksPrePublishErrors.new(INPUT_WHITESPACE_ERROR, { "input" => input["name"] })) if input["name"] =~ /\s/
        @errors.append(Errors::StacksPrePublishErrors.new(INPUT_LENGTH_ERROR, { "input" => input["name"] })) if input["name"].length > 1024
      end

      # assign value default based on type
      value = default_value_for_type(input["type"]) if input.key? "type"

      if input.key? "validvalues"
        # ensure all validvalues provided are of the defined type
        if (type = input.fetch("type", nil)).present?
          input["validvalues"].each do |valid_value|
            @errors.append(Errors::StacksPrePublishErrors.new(VALID_VALUES_MATCH_ERROR, { "valid_value" => valid_value, "received_type" => type_map(valid_value.class), "expected_type" => type })) if type_map(valid_value.class) != type
          end
        end

        # assign the first validvalue
        value = input["validvalues"].first
      end

      if input.key? "default"
        # ensure default value is of the defined type
        @errors.append(Errors::StacksPrePublishErrors.new(DEFAULT_VALUE_MATCH_ERROR, { "received_type" => type_map(input["default"].class), "expected_type" => type })) if (type = input.fetch("type", nil)).present? && type_map(input["default"].class) != type

        # assign default value
        value = input["default"]
      end

      if @values.key? input["name"]
        # ensure values.yml value is of the defined type
        @errors.append(Errors::StacksPrePublishErrors.new(VALUES_MATCH_ERROR, { "received_type" => type_map(@values[input["name"]].class), "expected_type" => type })) if (type = input.fetch("type", nil)).present? && type_map(@values[input["name"]].class) != type

        # assign values.yml value
        value = @values[input["name"]]
      end

      # input value couldn't be inferred
      if value.nil?
        inputs_without_value << input["name"]
      else
        @values[input["name"]] = value
      end
    end

    [inputs_without_value, inputs_set]
  end

  def populate_input_references_with_type(config, schema, input_references_with_type)
    # get the expected type or assume object by default
    expected_type = schema.fetch("type", "object")

    if expected_type == "object"
      # don't dig down deeper if current object doesn't meet expected type
      unless config.class == Hash
        @errors.append(Errors::StacksPrePublishErrors.new(WRONG_TYPE_ERROR, { "received_type" => type_map(config.class), "expected_type" => expected_type }))
        return
      end

      # dig down further for each key value
      config.each do |key, value|
        populate_input_references_with_type(value, schema_for(schema, [key]), input_references_with_type)
      end
    elsif expected_type == "array"
      # don't dig down deeper if current object doesn't meet expected type
      unless config.class == Array
        @errors.append(Errors::StacksPrePublishErrors.new(WRONG_TYPE_ERROR, { "received_type" => type_map(config.class), "expected_type" => expected_type }))
        return
      end

      # dig down element wise based on schema
      item_schema = schema_from_ref(schema["items"])
      config.each do |c|
        populate_input_references_with_type(c, item_schema, input_references_with_type)
      end

    # care only if it is an input reference, else handled by schema validation
    elsif is_input_reference?(config)
      input_name = config[3..-3].strip.split(".")
      if input_name.length == 2 && input_name[0] == "inputs"
        # already seen a reference to input but with different type expected
        if input_references_with_type.key?(input_name[1]) && input_references_with_type[input_name[1]] != schema["type"]
          @errors.append(Errors::StacksPrePublishErrors.new(INCONSISTENT_REFERENCE_ERROR, { "input" => input_name[1], "types" => [schema["type"], input_references_with_type[input_name[1]]] }))
          return
        end

        # assign type of input based on schema
        input_references_with_type[input_name[1]] = schema["type"]
      end
    end
  end

  def default_value_for_type(type)
    DEFAULT_VALUE_MAP.fetch type, nil
  end

  def type_map(type)
    TYPE_MAP.fetch type, "invalid"
  end

  # get the children schema based on path
  def schema_for(parent_schema, path)
    return parent_schema if path.empty?
    raise Errors::StacksPrePublishErrors.new("Invalid stack.yml.") if parent_schema.nil?

    # handling if current schema is for an array
    current_schema = if parent_schema.key?("type") && parent_schema["type"] == "array"
      parent_schema["items"]
    else
      parent_schema
    end

    # populating current schema from ref
    current_schema = schema_from_ref(current_schema)

    # getting the next level schema
    current_schema = current_schema["properties"][path.shift]
    schema_for(schema_from_ref(current_schema), path)
  end

  # get schema from ref
  def schema_from_ref(parent_schema)
    if parent_schema.nil?
      raise Errors::StacksPrePublishErrors.new("Invalid stack.yml.")
    elsif parent_schema.key?("$ref")
      definition_path = parent_schema["$ref"].split("/")

      raise Errors::StacksPrePublishErrors.new("Invalid stack schema.") if definition_path.shift != "#"

      parent_schema = @stack_schema
      definition_path.each do |key|
        parent_schema = parent_schema[key]
      end
    end

    parent_schema
  end

  TYPE_MAP = {
    Integer => "integer",
    String => "string",
    TrueClass => "boolean",
    FalseClass => "boolean",
    Float => "integer",
    Array => "array"
  }.freeze

  DEFAULT_VALUE_MAP = {
    "integer" => 0,
    "string" => "sample_string",
    "boolean" => false
  }.freeze
end
