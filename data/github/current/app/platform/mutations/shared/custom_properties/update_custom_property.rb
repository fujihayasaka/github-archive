# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    module Shared
      module CustomProperties
        module UpdateCustomProperty
          extend T::Helpers
          extend ActiveSupport::Concern

          include Kernel
          include CustomPropertiesCore::Errors

          abstract!

          requires_ancestor { Platform::Mutations::Base }

          included do
            T.bind(self, T.class_of(Platform::Mutations::Base))

            # value_type and property_name cannot be updated once created
            argument :description, GraphQL::Types::String, "The updated description of the custom property.", required: false
            argument :allowed_values, [GraphQL::Types::String], "The updated allowed values for the custom property.", required: false
            argument :required, GraphQL::Types::Boolean, "Whether the updated custom property is required.", required: false
            argument :default_value, GraphQL::Types::String, "The updated default value for the custom property if the property is required.", required: false
            argument :regex, GraphQL::Types::String, "The regex pattern that the value of the custom property must match, if the `value_type` is `string`.", required: false
          end

          def resolve(**inputs)
            begin
              custom_property = inputs[:custom_property]

              existing_input_fields = {
                property_name: custom_property.property_name,
                value_type: custom_property.value_type,
                required: custom_property.required,
                default_value: custom_property.default_value,
                description: custom_property.description,
                allowed_values: custom_property.allowed_values,
                values_editable_by: custom_property.values_editable_by,
              }

              resolved_input_fields = { **existing_input_fields, **inputs.except(:custom_property) }
              source = custom_property.source

              update_custom_property(source, resolved_input_fields, inputs)
            rescue InvalidDefinition, ArgumentError, DefinitionDeletionAllowValueInUseError => exception
              raise Errors::Unprocessable.new(exception.message)
            end
          end

          private

          sig { abstract.params(source: CustomPropertiesCore::PropertySource, input_fields: T::Hash[Symbol, T.untyped], inputs: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
          def update_custom_property(source, input_fields, inputs); end
        end
      end
    end
  end
end
