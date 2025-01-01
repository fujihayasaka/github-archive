# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Conditions
    class RepositoryPropertiesTarget < ConditionTarget

      PropertyParam = T.type_alias { { "name" => String, "property_values" => T::Array[String] } }
      PropertyParamWithSource = T.type_alias { { "name" => String, "property_values" => T::Array[String], "source" => T.nilable(String) } }

      sig { override.returns(T::Boolean) }
      def internal?
        false
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_ruleset_targets
        [:branch, :tag, :push, :repository]
      end

      # Sources that support this condition target
      sig { override.returns(T::Array[Symbol]) }
      def supported_sources
        [:organization, :business]
      end

      sig { override.returns(TargetObject) }
      def target_object
        TargetObject::Repository
      end

      sig { override.returns(T::Array[Targetable::Attribute]) }
      def targeted_attributes
        [Targetable::Attribute::RepositoryCustomProperties, Targetable::Attribute::RepositorySystemProperties]
      end

      sig do
        override.params(
          target_attributes: T::Hash[Targetable::Attribute, T.untyped],
          parameters: T::Hash[String, T.untyped],
        ).returns(T::Boolean)
      end
      def run_condition(target_attributes, parameters)
        custom_properties = target_attributes[Targetable::Attribute::RepositoryCustomProperties] || {}
        system_properties = target_attributes[Targetable::Attribute::RepositorySystemProperties] || {}

        return false if parameters["include"].blank? && parameters["exclude"].blank?

        matches_include = evaluate_repo_properties(custom_properties, system_properties, parameters["include"], false)
        matches_include ||= T.cast(parameters["include"].blank?, T::Boolean)
        matches_exclude = evaluate_repo_properties(custom_properties, system_properties, parameters["exclude"], true)

        matches_include && !matches_exclude
      end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root(validator: method(:ensure_valid_props_include_exclude_condition))

        property_schema = ParameterSchema::Object.new(name: "property_target_definition", display_name: "Property configuration",
          description: "A property that must match")
        property_schema.add_field(ParameterSchema::Field.new(name: "name", display_name: "Property name",
          type: :string, required: true, description: "The name of the property"))
        property_schema.add_field(ParameterSchema::Array.new(name: "property_values", display_name: "Accepted values",
          content_type: :string, required: true, description: "The values to match for", aliases: ["values"]))
        property_schema.add_field(ParameterSchema::Field.new(name: "source", display_name: "Property source",
          type: :string, required: false, description: "The source of the property. Choose 'custom' or 'system'. Defaults to 'custom' if not specified", allowed_values: %w[custom system], default_value: "custom"))

        schema.add_field(ParameterSchema::Array.new(name: "include", display_name: "Included properties",
          required: true, content_type: :object, content_object: property_schema, description: "Array of repository properties that must match"))
        schema.add_field(ParameterSchema::Array.new(name: "exclude", display_name: "Excluded properties",
          required: true, content_type: :object, content_object: property_schema, description: "Array of repository properties that must not match."))

        schema
      end

      private

      sig { params(custom_properties: T::Hash[String, T.untyped], system_properties: T::Hash[String, T.untyped], parameters: T::Array[PropertyParam], any_match: T::Boolean).returns(T::Boolean) }
      def evaluate_repo_properties(custom_properties, system_properties, parameters, any_match)
        sorted_properties_by_source = parameters.group_by { |property| property["source"] }
        system_params = sorted_properties_by_source.fetch("system", [])
        custom_params = sorted_properties_by_source.fetch("custom", []) + sorted_properties_by_source.fetch(nil, [])

        return false if system_params.empty? && custom_params.empty?

        custom_properties_result = false
        system_properties_result = false

        custom_properties_result = evaluate_custom_properties(custom_properties, custom_params, any_match:)
        system_properties_result = evaluate_system_properties(system_properties, system_params, any_match:)

        if any_match
          custom_properties_result || system_properties_result
        else
          custom_properties_result && system_properties_result
        end
      end

      sig { params(custom_properties: T::Hash[String, T.untyped], custom_params: T::Array[PropertyParam], any_match: T::Boolean).returns(T::Boolean) }
      def evaluate_custom_properties(custom_properties, custom_params, any_match:)
        return !any_match unless custom_params.present?

        condition = custom_params.map { |param| { name: param["name"], values: param["property_values"] } }
        if FeatureFlag.vexi.enabled?(:custom_properties_domain_isolation, default: false)
          Repositories.domain.custom_properties.properties_match_conditions?(custom_properties, condition, match_type: any_match ? :any : :all)
        else
          Repositories.domain.custom_properties.evaluate_effective_custom_properties(custom_properties, condition, any_match:)
        end
      end

      sig { params(params: T::Array[PropertyParam]).returns(T::Hash[String, T::Array[String]]) }
      def convert_condition_to_hash(params)
        params.each_with_object({}) do |param, condition|
          name = param["name"]
          values = param["property_values"]

          condition[name] = values
        end
      end

      sig { params(system_properties:  T::Hash[String, T.untyped], system_params: T::Array[PropertyParam], any_match: T::Boolean).returns(T::Boolean) }
      def evaluate_system_properties(system_properties, system_params, any_match:)
        return !any_match unless system_params.present?

        ::RepositoryRulesets::SystemProperties.evaluate(system_properties, system_params, any_match:)
      end

      sig do
        params(
          context: RuleEngine::ParameterSchema::ValidationContext,
          params: T::Hash[String, T::Array[PropertyParamWithSource]],
          errors: T::Array[T::Hash[T.untyped, T.untyped]]
        ).void
      end
      def ensure_valid_props_include_exclude_condition(context, params, errors)
        ruleset_source = context.root["ruleset_source"]
        return errors unless ruleset_source.is_a?(Organization)

        descriptors = RepositoryRulesets::PropertyDescriptors.get_descriptors(ruleset_source)
        return errors if descriptors.empty?

        valid_params = get_valid_include_exclude_param(errors, params)

        validate_property_names_and_values(errors, descriptors, valid_params, context)
        validate_duplicate_properties(errors, descriptors, valid_params)
      end

      sig do
        params(
          errors: T::Array[T::Hash[T.untyped, T.untyped]],
          params: T::Hash[String, T::Array[PropertyParamWithSource]]
        )
        .returns(T::Array[PropertyParamWithSource])
      end
      def get_valid_include_exclude_param(errors, params)
        valid_include = errors.find { |error| error[:field] == "include" && error[:error_code] == :invalid } ? [] : params["include"] || []
        valid_exclude = errors.find { |error| error[:field] == "exclude" && error[:error_code] == :invalid } ? [] : params["exclude"] || []

        valid_include + valid_exclude
      end

      sig do
        params(
          errors: T::Array[T::Hash[T.untyped, T.untyped]],
          descriptors: T::Array[RepositoryRulesets::PropertyDescriptor],
          properties: T.nilable(T::Array[PropertyParamWithSource]),
          context: T.nilable(RuleEngine::ParameterSchema::ValidationContext),
        ).void
      end
      def validate_property_names_and_values(errors, descriptors, properties, context = nil)
        return unless properties

        properties.each do |param|
          property_name = param["name"]
          property_source = param["source"] || "custom"
          property_values = param["property_values"]

          descriptor = descriptors.find { |item| item.property_name == property_name && item.source == property_source }

          if descriptor
            validate_property_values(errors, descriptor, { name: property_name, values: property_values, source: property_source }, context)
          else
            errors << {
              error_code: :invalid,
              message: "Invalid property '#{property_name}' with source '#{property_source}'",
            }
          end
        end
      end

      sig do
        params(
          errors: T::Array[T::Hash[T.untyped, T.untyped]],
          descriptor: RepositoryRulesets::PropertyDescriptor,
          property: { name: String, values: T::Array[String], source: String },
          context: T.nilable(RuleEngine::ParameterSchema::ValidationContext),
        ).void
      end
      def validate_property_values(errors, descriptor, property, context = nil)
        is_valid = descriptor.validate(property[:values], context)
        return if is_valid

        errors << {
          error_code: :invalid,
          message: "Invalid value(s) for the #{property[:source]} property '#{property[:name]}'",
        }
      end

      sig do
        params(
          errors: T::Array[T::Hash[T.untyped, T.untyped]],
          descriptors: T::Array[RepositoryRulesets::PropertyDescriptor],
          valid_params: T::Array[PropertyParamWithSource],
        ).void
      end
      def validate_duplicate_properties(errors, descriptors, valid_params)
        grouped_params = valid_params.group_by { |p| [p["name"], p["source"]] }
        duplicate_params = grouped_params.values.select { |group| group.size > 1 }.flatten.uniq { |p| [p["name"], p["source"]] }

        non_multi_select_duplicates = duplicate_params.select do |param|
          descriptor = descriptors.find { |item| item.property_name == param["name"] && item.source == param["source"] }
          descriptor && descriptor.value_type != "multi_select"
        end

        return if non_multi_select_duplicates.empty?

        duplicate_names = non_multi_select_duplicates.map { |param| param["name"] }
        errors << {
          error_code: :invalid,
          message: "Duplicate property '#{duplicate_names.join(", ")}' found",
        }
      end
    end
  end
end
