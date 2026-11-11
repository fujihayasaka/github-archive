# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    module Shared
      module CreateCustomProperty
        extend T::Helpers
        extend ActiveSupport::Concern

        include Kernel
        include CustomPropertiesCore::Errors

        requires_ancestor { Platform::Mutations::Base }
        requires_ancestor { Platform::Mutations::Shared::ICustomProperty }

        included do
          T.bind(self, T.class_of(Platform::Mutations::Base))

          argument :source_id, GraphQL::Types::ID, "The global relay id of the source in which a new custom property should be created in.", required: true, loads: Unions::CustomPropertySource
          argument :property_name, GraphQL::Types::String, "The name of the custom property.", required: true
          argument :description, GraphQL::Types::String, "The description of the custom property.", required: false
          argument :allowed_values, [GraphQL::Types::String], "The allowed values for the custom property.", required: false
          argument :value_type, Enums::CustomPropertyValueType, "The value type for the custom property.", required: true
          argument :required, GraphQL::Types::Boolean, "Whether the custom property is required.", required: false
          argument :default_value, GraphQL::Types::String, "The default value for the custom property if the property is required.", required: false
          argument :regex, GraphQL::Types::String, "The regex pattern that the value of the custom property must match, if the `value_type` is `string`.", required: false
        end

        def resolve(source:, **inputs)
          begin
            definition = domain.save_definition(source, **inputs.symbolize_keys, property_name: inputs[:property_name])
            transform_result(definition)
          rescue DefinitionLimitReachedError, InvalidDefinition, ArgumentError, DefinitionDeletionAllowValueInUseError => exception
            raise Errors::Unprocessable.new(exception.message)
          end
        end
      end
    end
  end
end
