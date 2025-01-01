# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Conditions
    class RepositoryPropertiesTarget < ConditionTarget

      sig { override.returns(T::Boolean) }
      def internal?
        false
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_ruleset_targets
        [:branch, :tag, :push, :member_privilege]
      end

      # Sources that support this condition target
      sig { override.returns(T::Array[Symbol]) }
      def supported_sources
        [:organization, :business]
      end

      sig { override.returns(String) }
      def target_object
        "repository"
      end

      sig do
        override.params(
          targetable: Targetable,
          ruleset_target: String,
          parameters: T.untyped
        ).returns(T::Boolean)
      end
      def run_condition(targetable, ruleset_target, parameters)
        return false unless (repository = targetable.repository)
        return false unless repository.owner.is_a?(Organization)

        check_repo_properties(repository, parameters["include"]) && !check_repo_properties(repository, parameters["exclude"])
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
          required: true, content_type: :object, content_object: property_schema, description: "Array of repository properties that must match", validator: method(:ensure_present)))
        schema.add_field(ParameterSchema::Array.new(name: "exclude", display_name: "Excluded properties",
          required: true, content_type: :object, content_object: property_schema, description: "Array of repository properties that must not match."))

        schema
      end

      private

      sig do
        params(
          context: RuleEngine::ParameterSchema::ValidationContext,
          include: T::Array[{ "name": String, "property_values": T::Array[String], "source": T.nilable(String) }],
          errors: T::Array[T::Hash[T.untyped, T.untyped]])
        .void
      end
      def ensure_present(context, include, errors)
        return errors unless GitHub.flipper[:forbid_property_rule_without_include].enabled?
        return errors if include.any?

        errors << {
          error_code: :invalid,
          message: "At least one target is required",
        }
      end

      sig { params(repository: ::Repository, parameters: T::Array[{ "name": String, "property_values": T::Array[String] }]).returns(T::Boolean) }
      def check_repo_properties(repository, parameters)
        sorted_properties_by_source = parameters.group_by { |property| property["source"] }
        system_params = sorted_properties_by_source.fetch("system", [])
        custom_params = sorted_properties_by_source.fetch("custom", []) + sorted_properties_by_source.fetch(nil, [])

        return false if system_params.empty? && custom_params.empty?

        check_properties_by_source(repository, custom_params, "custom") && check_properties_by_source(repository, system_params, "system")
      end

      sig { params(repository: ::Repository, params: T::Array[{ "name": String, "property_values": T::Array[String] }], source: String).returns(T::Boolean) }
      def check_properties_by_source(repository, params, source)
        values = RepositoryRulesets::CustomProperties.get_property_values(repository, source, params.map { |property| property["name"] })
        check_values(values, params)
      end

      sig { params(properties: T::Hash[String, T.nilable(CustomProperties::PropertyValue)], to_match: T::Array[{ "name": String, "property_values": T::Array[String] }]).returns(T::Boolean) }
      def check_values(properties, to_match)
        to_match.all? do |required|
          required_name = required["name"]
          required_values = required["property_values"]

          (required_values & Array(properties[required_name])).present?
        end
      end

      sig do
        params(
          context: RuleEngine::ParameterSchema::ValidationContext,
          params: T::Hash[String, T::Array[{ "name": String, "property_values": T::Array[String], "source": T.nilable(String) }]],
          errors: T::Array[T::Hash[T.untyped, T.untyped]]
        ).void
      end
      def ensure_valid_props_include_exclude_condition(context, params, errors)
        return errors unless GitHub.flipper[:ruleset_ensure_valid_props_and_values].enabled?

        ruleset_source = context.root["ruleset_source"]
        return errors unless ruleset_source.is_a?(Organization)

        descriptors = RepositoryRulesets::CustomProperties.get_property_descriptors(ruleset_source)
        return errors if descriptors.empty?

        valid_params = get_valid_include_exclude_param(errors, params)

        if ruleset_source.feature_enabled?(:rules_exclude_public_repositories_from_targeting)
          validate_property_names_and_values(errors, descriptors, valid_params, context)
        else
          validate_property_names_and_values(errors, descriptors, valid_params)
        end
      end

      sig do
        params(
          errors: T::Array[T::Hash[T.untyped, T.untyped]],
          params: T::Hash[String, T::Array[{ "name": String, "property_values": T::Array[String], "source": T.nilable(String) }]]
        )
        .returns(T::Array[{ "name": String, "property_values": T::Array[String], "source": T.nilable(String) }])
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
          properties: T.nilable(T::Array[{ "name": String, "property_values": T::Array[String], "source": T.nilable(String) }]),
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
    end
  end
end
