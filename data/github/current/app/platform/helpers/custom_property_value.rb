# typed: strict
# frozen_string_literal: true

module Platform
  module Helpers
    class CustomPropertyValue
      sig { returns(String) }
      attr_reader :property_name

      sig { returns(T.nilable(CustomPropertiesCore::PropertyValue)) }
      attr_reader :value

      sig { returns(CustomPropertiesCore::IPropertyTarget) }
      attr_reader :target

      sig { params(property_name: String, value: T.nilable(CustomPropertiesCore::PropertyValue), target: CustomPropertiesCore::IPropertyTarget).void }
      def initialize(property_name:, value:, target:)
        @property_name = property_name
        @value = value
        @target = target
      end
    end
  end
end
