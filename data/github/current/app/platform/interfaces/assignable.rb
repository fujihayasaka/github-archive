# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Assignable
      extend T::Helpers

      requires_ancestor { GraphQL::Schema::Object }

      include Platform::Interfaces::Base
      description "An object that can have users assigned to it."

      field :assignees, resolver: Resolvers::Assignees, description: "A list of Users assigned to this object.", connection: true

      field :suggested_assignees, resolver: Resolvers::SuggestedAssignees, description: "A list of suggested users to assign to this object", connection: true, required_capabilities: [:mobile_only_schema_mask]

      field :viewer_can_assign,
        Boolean,
        description: "Indicates if the viewer can edit assignees for this object.",
        required_capabilities: [:mobile_only_schema_mask],
        null: false

      def viewer_can_assign
        T.bind(self, GraphQL::Schema::Object)
        async_assignable = @object.is_a?(PullRequest) ? @object.async_issue : Promise.resolve(@object)

        async_assignable.then do |assignable|
          assignable.async_assignable_by?(actor: context[:viewer])
        end
      end
    end
  end
end
