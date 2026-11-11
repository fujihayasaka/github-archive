# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module CustomPropertyValueBase
      extend T::Helpers
      extend ActiveSupport::Concern

      requires_ancestor { GraphQL::Schema::Object }

      included do
        T.bind(self, T.class_of(GraphQL::Schema::Object))

        field :property_name, GraphQL::Types::String,
          description: "The name of the custom property.",
          null: false

        field :value, Scalars::CustomPropertyValue,
          description: "The value of the custom property.",
          null: false
      end
    end
  end
end
