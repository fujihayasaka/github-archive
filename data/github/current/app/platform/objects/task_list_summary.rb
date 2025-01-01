# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TaskListSummary < Platform::Objects::Base
      description "A summary of a task list of items."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, task_list_summary)
        permission.hidden_from_public?(self) # Update this authorization if we ever go public with this object
      end

      visibility :under_development
      scopeless_tokens_as_minimum

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      field :has_items, Boolean, method: :items?, null: false,
        description: "Are there any items in the task list?"

      field :item_count, Integer, null: false, description: "Count of items in the task list."

      field :complete_count, Integer, null: false,
        description: "Count of completed items in the task list."

      field :incomplete_count, Integer, null: false,
        description: "Count of items that haven't been completed in the task list."
    end
  end
end
