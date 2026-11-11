# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    module Shared
      module SetCustomPropertyValues
        extend T::Helpers
        extend ActiveSupport::Concern

        include Kernel
        include CustomPropertiesCore::Errors

        requires_ancestor { Platform::Mutations::Base }

        abstract!

        included do
          T.bind(self, T.class_of(Platform::Mutations::Base))
          argument :properties, [Inputs::CustomPropertyValueInput], "A list of custom property names and associated values to apply.", required: true
        end

        def resolve(properties:, **inputs)
          begin
            property_names = properties.map { |property| property[:property_name] }
            duplicate_properties = property_names.tally.select { |_prop, count| count > 1 }.keys

            raise Errors::Unprocessable, "Updated properties must be unique, found duplicates: #{duplicate_properties.join(', ')}" if duplicate_properties.any?

            properties_hash = properties.to_h { |property| [property[:property_name], property[:value]] }
            set_values_for(inputs, properties_hash)
          rescue ArgumentError, PropertyValidationError, EditPropertyPermissionError => ex
            raise Errors::Unprocessable, ex.message
          end
        end

        private

        # Sets the custom property values for the target object and returns the mutation result.
        sig do
          abstract.params(
            inputs: T::Hash[Symbol, T.untyped],
            properties: T::Hash[String, CustomPropertiesCore::PropertyValue],
          ).returns(T.untyped)
        end
        def set_values_for(inputs, properties); end
      end
    end
  end
end
