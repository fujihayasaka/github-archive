# typed: true
# frozen_string_literal: true

class GraphqlSchemaWriter < SchemaWriter

  # The following classes currently don't support graphql enums for their fields.
  # Enum field support was added after these classes were added and if we were to change the types to enums,
  # we may break existing rules
  UNSUPPORTED_ENUM_CLASSES = %w(
    BranchNamePattern
    CodeScanningTool
    CommitAuthorEmailPattern
    CommitMessagePattern
    CommitterEmailPattern
    PropertyTargetDefinition
    TagNamePattern
  ).freeze

  sig { params(dry: T::Boolean).void }
  def initialize(dry)
    @file_type = :graphql
    @dry = dry
    super()
  end

  sig { params(dry: T::Boolean).returns(GraphqlSchemaWriter) }
  def self.instance(dry)
    @instance ||= new(dry)
  end

  #  ================== call parent ==================

  # Retrieves the parent instance of the class to write the contents to the files in the path if there
  # are changes. Returns the current state of the writer's @dry_run_results if doing a dry run
  sig { params(path: String, contents: String, dry: T::Boolean).void }
  def write_gql_file(path, contents, dry: false)
    write(path, contents, dry: dry)
  end

  # ================== end call parent ==================

  # Formats the path to write the file to. And then calls for the file to be written (if not a dry run)
  sig { params(class_name: String, class_string: String, folder: String).void }
  def write_schema_file(class_name, class_string, folder:)
    write_gql_file("app/platform/#{folder}/repository_rules/#{class_name.underscore}.rb", class_string, dry: @dry)
  end

  # TODO: description
  sig { params(class_name: String, description: String, rule_types: T::Hash[String, RuleEngine::BaseRule]).void }
  def write_enum_file(class_name, description, rule_types)
    value_string = ""

    rule_types.each do |rule_type_key, rule_type_value|
      rule_description = rule_type_value.description || rule_type_key.humanize
      # TODO: Potentially replace beta_api_note with .beta flag. They seem to be doing the same thing anyway
      rule_description += " NOTE: This rule is in preview and subject to change" if rule_type_value.beta_api_note
      value_string += "      value #{rule_type_key.upcase.dump}, #{rule_description.dump}, value: #{rule_type_key.dump}"
      # If we are publishing the API early, we can ignore the feature flag
      if rule_type_value.feature_flag.present? && !rule_type_value.publish_api
        value_string += ", feature_flag: :#{rule_type_value.feature_flag}"
      end
      value_string += "\n"
    end

    comment = "the supported rule parameter schemas"
    input_data = generate_header(comment)

    input_data += <<~INPUT
      module Platform
        module Enums
          class #{class_name} < Platform::Enums::Base
            description "#{description}"

      #{value_string.chomp}
          end
        end
      end
    INPUT

    write_gql_file("app/platform/enums/#{class_name.underscore}.rb", input_data, dry: @dry)
  end

  # Note: For rules that have a parameter schema and are not a toggle rule
  # TODO: description
  sig { params(class_name: String, description: String, rule_parameters_by_type: T::Hash[String, String], generated_classes_with_feature_flags: T::Hash[String, T.nilable(Symbol)]).void }
  def write_input_union_file(class_name, description, rule_parameters_by_type, generated_classes_with_feature_flags)
    argument_string = ""

    rule_parameters_by_type.each do |rule_type, param_class|
      feature_flag = !!generated_classes_with_feature_flags[rule_type] ? ", feature_flag: :#{generated_classes_with_feature_flags[rule_type]}" : ""

      argument_string += "      argument :#{rule_type}, Inputs::RepositoryRules::#{param_class}Input, \"Parameters used for the `#{rule_type}` rule type\"#{feature_flag}, required: false\n"
    end

    comment = "the supported rule parameter schemas"
    input_data = generate_header(comment)

    input_data += <<~INPUT
      module Platform
        module Inputs
          class #{class_name} < Platform::Inputs::Base
            # Once `oneOf` is supported in GraphQL, this class can make use of it
            description "#{description} Only one of the fields should be specified."

      #{argument_string.chomp}
          end
        end
      end
    INPUT

    write_gql_file("app/platform/inputs/#{class_name.underscore}.rb", input_data, dry: @dry)
  end

  # Note: For rules that have a parameter schema and are not a toggle rule
  # TODO: description
  sig { params(class_name: String, rule_parameters_by_type: T::Hash[String, String]).void }
  def write_model_union_file(class_name, rule_parameters_by_type)
    when_string = ""
    rule_parameters_by_type.each do |rule_type, param_class|
      when_string += <<-WHEN
    when "#{rule_type}"
      "#{param_class}"
    WHEN
    end

    comment = "the supported rule parameter schemas"
    model_data = generate_header(comment)

    model_data += <<~MODEL
      class Platform::Models::#{class_name}
        attr_reader :ruleset, :parameters, :rule_type

        def initialize(ruleset, parameters, platform_type: nil, rule_type: nil)
          @ruleset = ruleset
          @parameters = parameters
          @platform_type = platform_type
          @rule_type = rule_type
        end

        def platform_type_name
          return @platform_type if @platform_type

          case rule_type
      #{when_string.chomp}
          end
        end
      end
    MODEL

    write_gql_file("app/platform/models/#{class_name.underscore}.rb", model_data, dry: @dry)
  end

  # TODO: description
  sig { params(class_name: String, schema: RuleEngine::ParameterSchema::Object, description: String, feature_flag: T.nilable(Symbol), publish_api: T.nilable(T::Boolean)).void }
  def write_graphql_input_class(class_name, schema, description, feature_flag: nil, publish_api: nil)
    argument_string = ""
    schema.fields.sort_by(&:name).each do |field|
      unless field.internal
        argument_string += "        #{graphql_argument_for_field(field, class_name:)}\n"
      end
    end

    comment = "the supported rule parameter schemas"
    input_data = generate_header(comment)

    input_data += <<~INPUT
      module Platform
        module Inputs
          module RepositoryRules
            class #{class_name}Input < Platform::Inputs::Base
              description #{description.dump}
      #{"        feature_flag :#{feature_flag}\n" if feature_flag && !publish_api}
      #{argument_string.chomp}
            end
          end
        end
      end
    INPUT

    write_schema_file(class_name + "Input", input_data, folder: "inputs")
  end

  # Note: For rules that have a parameter schema and are not a toggle rule
  # TODO: description
  sig { params(class_name: String, description: String, rule_parameters: T::Array[String]).void }
  def write_union_file(class_name, description, rule_parameters)
    type_string = ""
    rule_parameters.each do |param_type|
      type_string += "        Objects::RepositoryRules::#{param_type},\n"
    end

    comment = "the supported rule parameter schemas"
    union_data = generate_header(comment)

    union_data += <<~UNION
      module Platform
        module Unions
          class #{class_name} < Platform::Unions::Base
            description "#{description}"

            possible_types(
      #{type_string.chomp}
            )
          end
        end
      end
    UNION

    write_gql_file("app/platform/unions/#{class_name.underscore}.rb", union_data, dry: @dry)
  end

  #  ============= helpers =============

  # TODO: description
  sig { params(field: RuleEngine::ParameterSchema::Base, class_name: T.nilable(String)).returns(T::Boolean) }
  def is_graphql_enum?(field, class_name)
    !UNSUPPORTED_ENUM_CLASSES.include?(class_name&.delete_suffix("Parameters")) &&
    (field.try(:allowed_options)&.present? || field.try(:allowed_values)&.present? || false)
  end

  # TODO: description
  sig { params(field: T.untyped, class_name: T.nilable(String)).returns(T.nilable(String)) }
  def graphql_argument_for_field(field, class_name:)
    if field.is_a?(RuleEngine::ParameterSchema::Field)
      create_graphql_argument(
        name: field.name,
        type: field.graphql_type,
        description: field.description_api,
        required: field.required,
        feature_flag: field.feature_flag,
        beta: field.beta_api_note,
        publish_api: field.publish_api,
        enum: is_graphql_enum?(field, class_name),
        class_name:
      )
    elsif field.is_a?(RuleEngine::ParameterSchema::Object)
      class_name = field.name.camelize + "Input"
      create_graphql_argument(
        name: field.name,
        type: class_name,
        description: field.description_api,
        required: field.required,
        feature_flag: field.feature_flag,
        beta: field.beta_api_note,
        publish_api: field.publish_api,
        object: true,
        class_name:
      )
    elsif field.is_a?(RuleEngine::ParameterSchema::Array)
      if field.content_type == :object
        class_name = field.content_object.name.camelize + "Input"
        create_graphql_argument(
          name: field.name,
          type: class_name,
          description: field.description_api,
          required: field.required,
          feature_flag: field.feature_flag,
          beta: field.beta_api_note,
          publish_api: field.publish_api,
          object: true,
          array: true,
          class_name:
        )
      else
        create_graphql_argument(
          name: field.name,
          type: field.graphql_content_type,
          description: field.description_api,
          required: field.required,
          feature_flag: field.feature_flag,
          beta: field.beta_api_note,
          publish_api: field.publish_api,
          enum: is_graphql_enum?(field, class_name),
          array: true,
          class_name:
        )
      end
    end
  end

  sig { params(field_name: String).returns(T.nilable(String)) }
  def fix_graphql_name(field_name)
    # "context" is a special platform method name that cannot be overriden
    if field_name == "context"
      "status_context"
    end
  end

  # TODO: description
  sig do
    params(
      name: String,
      type: String,
      description: String,
      required: T::Boolean,
      feature_flag: T.nilable(Symbol),
      beta: T::Boolean,
      publish_api: T.nilable(T::Boolean),
      object: T::Boolean,
      array: T::Boolean,
      enum: T::Boolean,
      class_name: T.nilable(String)
    ).returns(String)
  end
  def create_graphql_argument(name:, type:, description:, required:, feature_flag: nil, beta: false, publish_api: nil, object: false, array: false, enum: false, class_name: nil)
    if enum
      type_string = "Enums::RepositoryRules::#{class_name ? "#{class_name.delete_suffix("Parameters")}#{name.camelcase}" : "#{name.camelcase}"}"
    else
      type_string = object ? "Inputs::RepositoryRules::#{type}" : type
    end
    type_string = "[#{type_string}]" if array

    if feature_flag.present? && beta.present?
      description += " This argument is in beta and subject to change. #{description.dump}"
    end
    text_string = "argument :#{name}, #{type_string}, #{description.dump}, required: #{required}"
    text_string << ", feature_flag: :#{feature_flag}" unless feature_flag.nil? || publish_api
    text_string
  end

  # TODO: description
  sig do params(
    field: T.untyped,
    type: String,
    object: T::Boolean,
    array: T::Boolean,
    enum: T::Boolean,
    class_name: T.nilable(String)).returns(String)
  end
  def create_graphql_field(
    field:,
    type:,
    object: false,
    array: false,
    enum: false,
    class_name: nil)
    swap_method_name = fix_graphql_name(field.name)

    field_text = []
    if enum
      # enum fields are written when creating the graphql field
      write_graphql_enum_field_file(field, class_name:)
      type_string = "Enums::RepositoryRules::#{class_name ? "#{class_name.delete_suffix("Parameters")}#{field.name.camelcase}" : "#{field.name.camelcase}"}"
    else
      type_string = (object ? "Objects::RepositoryRules::" : "") + type
    end
    type_string = "[#{type_string}]" if array

    field_text << "        field :#{field.name}, #{type_string},"
    description = if field.feature_flag.present? && field.beta_api_note
      "This field is in beta and subject to change. #{field.description_api.dump}"
    else
      field.description_api.dump
    end
    field_text << "          description: #{description},"
    # add a feature flag if a feature flag is present unless explictly published
    field_text << "          feature_flag: :#{field.feature_flag}," unless field.feature_flag.nil? || field.publish_api
    # Boolean values should never be nil for GQL
    field_text << "          null: #{type != "Boolean" && field.required == false}"
    if swap_method_name
      field_text[field_text.length - 1] = field_text[field_text.length - 1] + ","
      field_text << "          resolver_method: :#{swap_method_name}"
    end
    field_text << ""
    field_text << "        def #{swap_method_name || field.name}"
    field_text << if array
      if object
        <<-ARRAY_METHOD
          ArrayWrapper.new(@object.parameters[\"#{field.name}\"].map do |param|
            Platform::Models::RepositoryRuleParameters.new(@object.ruleset, param, platform_type: "#{type}")
          end)
        ARRAY_METHOD
      else
        "          ArrayWrapper.new(@object.parameters[\"#{field.name}\"])"
      end.chomp
    else
      value = object ? "Platform::Models::RepositoryRuleParameters.new(@object.ruleset, @object.parameters[\"#{field.name}\"], platform_type: \"#{type}\")" : "@object.parameters[\"#{field.name}\"]"
      # Ensure Boolean values are not nil
      if type == "Boolean" && !field.required
        value += " || #{field.default_value.present? ? field.default_value : "false"}"
      end
      "          #{value}"
    end

    field_text << "        end"
    field_text.join("\n") + "\n"
  end

  # TODO: description
  sig { params(field: T.untyped, feature_flag: T.nilable(Symbol), class_name: T.nilable(String)).returns(T.nilable(String)) }
  def graphql_field_for_field(field, feature_flag: nil, class_name: nil)
    if field.is_a?(RuleEngine::ParameterSchema::Field)
      create_graphql_field(field: field, type: field.graphql_type, enum: is_graphql_enum?(field, class_name), class_name:)
    elsif field.is_a?(RuleEngine::ParameterSchema::Object)
      class_name = field.name.camelize
      subparameter_class = write_rule_class(class_name, field, field.description_api, feature_flag:)

      create_graphql_field(field: field, type: class_name, object: true, class_name:)
    elsif field.is_a?(RuleEngine::ParameterSchema::Array)
      if field.content_type == :object
        object = field.content_object
        class_name = object.name.camelize
        subparameter_class = write_rule_class(class_name, object, object.description, feature_flag:)

        create_graphql_field(field: field, type: class_name, object: true, array: true, class_name:)
      else
        create_graphql_field(field: field, type: field.graphql_content_type, enum: is_graphql_enum?(field, class_name), array: true, class_name:)
      end
    end
  end

  # ============= end helpers =============

  # TODO: description
  sig { params(field: T.any(RuleEngine::ParameterSchema::Field, RuleEngine::ParameterSchema::Array), class_name: T.nilable(String)).void }
  def write_graphql_enum_field_file(field, class_name: nil)
    class_name = class_name&.delete_suffix("Parameters")
    enum_name = class_name ? "#{class_name}#{field.name.camelcase}" : "#{field.name.camelcase}"
    enum_values = ""
    feature_flagged = ""

    if field.allowed_options.present?
      field.allowed_options&.each do |option|
        enum_values += "        value \"#{option[:value].upcase}\", \"#{option[:description] || option[:display_name]}\", value: \"#{option[:value]}\"\n"
      end
    elsif field.is_a?(RuleEngine::ParameterSchema::Field)
      field.allowed_values&.each do |value|
        enum_values += "        value \"#{value.upcase}\", \"#{value}\", value: \"#{value}\"\n"
      end
    end

    if field.feature_flag.present?
      feature_flagged += "        feature_flag :#{field.feature_flag}\n\n"
    end

    comment = "the enums for"
    comment += if class_name.present?
      " the '#{class_name}' field '#{field.name}'\n"
    else
      " the '#{field.name}' field\n"
    end

    text = generate_header(comment)
    text += <<~ENUM
      module Platform
        module Enums
          module RepositoryRules
            class #{enum_name} < Platform::Enums::Base
              description "#{field.description_api}"
      #{feature_flagged.chomp}
      #{enum_values.chomp}
            end
          end
        end
      end
    ENUM

    write_gql_file("app/platform/enums/repository_rules/#{enum_name.underscore}.rb", text, dry: @dry)
  end

  # TODO: description
  sig { params(generated_condition_classes_by_type: T::Hash[String, T::Hash[Symbol, Symbol]]).void }
  def write_condition_union_class(generated_condition_classes_by_type)
    field_string = ""
    generated_condition_classes_by_type.each do |type, value|
      class_name = value[:name]
      feature_flag = value[:feature_flag]
      modifier_string = ""
      modifier_string += ", feature_flag: :#{feature_flag}\n" if feature_flag
      field_string += <<-FIELD
        field :#{type}, Objects::RepositoryRules::#{class_name},
          description: "Configuration for the #{type} condition",
          null: true#{modifier_string.chomp}

        def #{type}
          condition = @object.conditions.find_by(target: "#{type}")
          return nil unless condition
          Platform::Models::RepositoryRuleParameters.new(@object.ruleset, condition.parameters, platform_type: "#{class_name}")
        end
        FIELD
      field_string += "\n"
    end

    comment = "the set of rule condition targets"
    class_string = generate_header(comment)
    class_string += <<~CLASS
    module Platform
      module Objects
        module RepositoryRules
          class RepositoryRuleConditions < Platform::Objects::Base
            description "Set of conditions that determine if a ruleset will evaluate"
            minimum_accepted_scopes ["public_repo"]

            # Determine whether the viewer can access this object via the API (called internally).
            # This is where Egress checks for OAuth scopes and GitHub Apps go.
            # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
            def self.async_api_can_access?(permission, object)
              permission.typed_can_access?("RepositoryRuleset", object.ruleset)
            end

            # Determine whether the viewer can see this object (called internally).
            # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
            def self.async_viewer_can_see?(permission, object)
              permission.typed_can_see?("RepositoryRuleset", object.ruleset)
            end

    #{field_string.rstrip}
          end
        end
      end
    end
    CLASS

    write_schema_file("RepositoryRuleConditions", class_string, folder: "objects")
  end

  # TODO: description
  sig { params(generated_condition_classes_by_type: T::Hash[String, T::Hash[Symbol, Symbol]]).void }
  def write_conditions_union_input_class(generated_condition_classes_by_type)
    argument_string = ""
    generated_condition_classes_by_type.each do |type, value|
      class_name = value[:name]
      feature_flag = value[:feature_flag]
      argument_string += "        #{create_graphql_argument(name: type, type: "Inputs::RepositoryRules::#{class_name}Input", description: "Configuration for the #{type} condition", required: false, feature_flag:)}\n"
    end

    comment = "the supported rule parameter schemas"
    input_data = generate_header(comment)

    input_data += <<~INPUT
      module Platform
        module Inputs
          module RepositoryRules
            class RepositoryRuleConditionsInput < Platform::Inputs::Base
              description "Specifies the conditions required for a ruleset to evaluate"

      #{argument_string.chomp}
            end
          end
        end
      end
    INPUT

    write_schema_file("RepositoryRuleConditionsInput", input_data, folder: "inputs")
  end

  # TODO: description
  sig { params(class_name: String, schema: RuleEngine::ParameterSchema::Object, description: String, feature_flag: T.nilable(Symbol), publish_api: T.nilable(T::Boolean)).void }
  def write_rule_class(class_name, schema, description, feature_flag: nil, publish_api: nil)
    field_string = ""
    schema.fields.sort_by(&:name).each do |field|
      unless field.internal
        field_string += "#{graphql_field_for_field(field, feature_flag:, class_name:)}\n"
      end
    end

    comment = if schema.root
      "the rule parameter schema for the `#{class_name.delete_suffix("Parameters")}` rule."
    else
      "the rule parameter schema type `#{class_name}`."
    end

    parameter_class_string = generate_header(comment)
    parameter_class_string += <<~CLASS
    module Platform
      module Objects
        module RepositoryRules
          class #{class_name} < Platform::Objects::Base
            description #{description.dump}
            minimum_accepted_scopes ["public_repo"]
    #{"        feature_flag :#{feature_flag}\n" if feature_flag && !publish_api }
            # Determine whether the viewer can access this object via the API (called internally).
            # This is where Egress checks for OAuth scopes and GitHub Apps go.
            # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
            def self.async_api_can_access?(permission, object)
              permission.typed_can_access?("RepositoryRuleset", object.ruleset)
            end

            # Determine whether the viewer can see this object (called internally).
            # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
            def self.async_viewer_can_see?(permission, object)
              permission.typed_can_see?("RepositoryRuleset", object.ruleset)
            end

    #{field_string.rstrip}
          end
        end
      end
    end
    CLASS

    write_graphql_input_class(class_name, schema, description, feature_flag:, publish_api:)
    write_schema_file(class_name, parameter_class_string, folder: "objects")
  end

  # TODO: description
  sig { params(class_name: String, schema: RuleEngine::ParameterSchema::Object, description: String, block_non_org_access: T::Boolean, feature_flag: T.nilable(Symbol)).void }
  def write_condition_class(class_name, schema, description, block_non_org_access: false, feature_flag: nil)
    field_string = ""
    modifier_string = ""
    modifier_string += "        feature_flag :#{feature_flag}\n" if feature_flag
    schema.fields.sort_by(&:name).each do |field|
      unless field.internal
        field_string += "#{graphql_field_for_field(field)}\n"
      end
    end

    can_access_string = if block_non_org_access
      <<~CAN_ACCESS
        object.ruleset.async_source.then do |source|
          if source.is_a?(::Organization)
            permission.access_allowed?(:manage_organization_ref_rules, resource: source, current_repo: nil, current_org: source, allow_integrations: true, allow_user_via_granular_actor: true)
          else
            permission.typed_can_access?("RepositoryRuleset", object.ruleset)
          end
        end
      CAN_ACCESS
    else
      <<~CAN_ACCESS
        permission.typed_can_access?("RepositoryRuleset", object.ruleset)
      CAN_ACCESS
    end
    can_access_string = add_spaces(can_access_string, 10)

    comment = "the condition schema type `#{class_name}`."
    condition_class_string = generate_header(comment)

    condition_class_string += <<~CLASS
      module Platform
        module Objects
          module RepositoryRules
            class #{class_name} < Platform::Objects::Base
              description #{description.dump}
              minimum_accepted_scopes ["public_repo"]
      #{modifier_string}
              # Determine whether the viewer can access this object via the API (called internally).
              # This is where Egress checks for OAuth scopes and GitHub Apps go.
              # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
              def self.async_api_can_access?(permission, object)
      #{can_access_string}
              end

              # Determine whether the viewer can see this object (called internally).
              # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
              def self.async_viewer_can_see?(permission, object)
                permission.typed_can_see?("RepositoryRuleset", object.ruleset)
              end

      #{field_string.rstrip}
            end
          end
        end
      end
    CLASS

    write_graphql_input_class(class_name, schema, description, feature_flag:)
    write_schema_file(class_name, condition_class_string, folder: "objects")
  end

  # TODO: description
  sig { void }
  def generate_graphql_schema
    generated_classes_by_type = {}
    generated_classes_with_feature_flags = {}

    configurable_types.each do |rule_type, impl|
      schema = impl.try(:parameter_schema)
      if schema && schema.has_visible_fields?
        name = rule_type.camelize + "Parameters"

        description = impl.description || "Parameters to be used for the #{rule_type} rule"
        description += " NOTE: This rule is in beta and subject to change" if impl.beta_api_note
        class_string = write_rule_class(name, schema, description, feature_flag: impl.feature_flag, publish_api: impl.publish_api)
        generated_classes_by_type[rule_type] = name
        # If we are publishing the API early, we can ignore the feature flag
        generated_classes_with_feature_flags[rule_type] = impl.feature_flag if impl.feature_flag && !impl.publish_api
      end
    end

    generated_condition_classes_by_type = {}
    RuleEngine::Conditions::Evaluator::TARGET_TYPES.each do |target_type, impl|
      schema = impl.try(:parameter_schema)
      feature_flag = impl.try(:feature_flag)
      if !impl.internal? && schema && !schema.empty?
        name = target_type.camelize + "ConditionTarget"

        class_string = write_condition_class(name, schema, "Parameters to be used for the #{target_type} condition",
          block_non_org_access: !impl.supported_sources.include?(:repository), feature_flag:)
        generated_condition_classes_by_type[target_type] = { name:, feature_flag: }
      end
    end

    # Rules
    write_union_file("RuleParameters", "Types which can be parameters for `RepositoryRule` objects.", generated_classes_by_type.values)
    write_input_union_file("RuleParametersInput", "Specifies the parameters for a `RepositoryRule` object.", generated_classes_by_type, generated_classes_with_feature_flags)
    write_enum_file("RepositoryRuleType", "The rule types supported in rulesets", RuleEngine::Evaluator::REGISTERED_RULES)

    write_model_union_file("RepositoryRuleParameters", generated_classes_by_type)

    # Conditions
    write_condition_union_class(generated_condition_classes_by_type)
    write_conditions_union_input_class(generated_condition_classes_by_type)
  end
end
