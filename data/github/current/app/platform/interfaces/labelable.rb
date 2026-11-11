# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Labelable
      extend T::Helpers

      requires_ancestor { GraphQL::Schema::Object }

      include Platform::Interfaces::Base
      description "An object that can have labels assigned to it."

      field :labels, resolver: Resolvers::Labels, description: "A list of labels associated with the object.", scope: true, connection: true, numeric_pagination_enabled: true

      field :viewer_can_label,
        Boolean,
        description: "Indicates if the viewer can edit labels for this object.",
        null: false

      def viewer_can_label
        T.bind(self, GraphQL::Schema::Object)
        @object.async_labelable_by?(actor: context[:viewer])
      end
    end
  end
end
