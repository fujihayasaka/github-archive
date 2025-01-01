# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectProgress < Platform::Objects::Base
      description "Project progress stats."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      minimum_accepted_scopes ["public_repo"]

      field :todo_count, Integer, "The number of to do cards.", null: false
      field :in_progress_count, Integer, "The number of in-progress cards.", null: false
      field :done_count, Integer, "The number of done cards.", null: false

      field :todo_percentage, Float, "The percentage of to do cards.", null: false
      field :in_progress_percentage, Float, "The percentage of in-progress cards.", null: false
      field :done_percentage, Float, "The percentage of done cards.", null: false

      field :enabled, Boolean, "Whether progress tracking is enabled and cards with purpose exist for this project", method: :enabled?, null: false
    end
  end
end
