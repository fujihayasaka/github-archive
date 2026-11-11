# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module CustomPropertyBase
      extend T::Helpers
      extend ActiveSupport::Concern

      requires_ancestor { GraphQL::Schema::Object }

      included do
        T.bind(self, T.class_of(GraphQL::Schema::Object))

        field :property_name, GraphQL::Types::String,
          description: "The name of the custom property.",
          null: false

        field :description, GraphQL::Types::String,
          description: "The description of the custom property.",
          null: true

        field :value_type, Enums::CustomPropertyValueType,
          description: "The value type of the custom property.",
          null: false

        field :allowed_values, [GraphQL::Types::String],
          description: "The allowed values for the custom property. Required if `value_type` is `single_select` or `multi_select`.",
          null: true

        field :required, GraphQL::Types::Boolean,
          description: "Whether the custom property is required.",
          null: true

        field :default_value, Scalars::CustomPropertyValue,
          description: "The default value of the custom property, if the property is `required`.",
          null: true

        field :source, Unions::CustomPropertySource,
          description: "The source type of the custom property.",
          null: false

        field :regex, GraphQL::Types::String,
          description: "The regex pattern that the value of the custom property must match, if the `value_type` is `string`.",
          null: true
      end
    end
  end
end
