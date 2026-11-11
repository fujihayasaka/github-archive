# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    module Shared
      module CustomProperties
        module CreateCustomProperty
          extend T::Helpers
          extend ActiveSupport::Concern

          include Kernel
          include CustomPropertiesCore::Errors

          abstract!

          requires_ancestor { Platform::Mutations::Base }

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

          def resolve(source:, property_name:, **inputs)
            begin
              duplicate_property_name = domain.get_definition(source, property_name)&.property_name
              raise Errors::Unprocessable.new("Failed to save custom property. Property already exists with similar name '#{duplicate_property_name}'. Property name uniqueness is case insensitive.") if duplicate_property_name.present?

              create_custom_property(source, property_name, inputs)
            rescue DefinitionLimitReachedError, InvalidDefinition, ArgumentError, DefinitionDeletionAllowValueInUseError => exception
              raise Errors::Unprocessable.new(exception.message)
            end
          end

          private

          sig { abstract.returns(CustomPropertiesCore::DomainAccessorBase) }
          def domain; end

          sig { abstract.params(source: CustomPropertiesCore::PropertySource, property_name: String, inputs: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
          def create_custom_property(source, property_name, inputs); end
        end
      end
    end
  end
end
