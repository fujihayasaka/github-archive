# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class BlameRange < Platform::Objects::Base
      description "Represents a range of information from a Git blame."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(_permission, _object)
        # To access this non Active Record object the caller already need to get permissions for a repo and a commit
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_git_object(object)
      end

      scopeless_tokens_as_minimum

      field :starting_line, Integer, description: "The starting line for the range", null: false

      def starting_line
        @object.lines.first[:lineno]
      end

      field :ending_line, Integer, description: "The ending line for the range", null: false

      def ending_line
        @object.lines.first[:lineno] + (@object.lines.length - 1)
      end

      field :commit, Objects::Commit, description: "Identifies the line author", null: false

      field :age, Integer, method: :scale, description: "Identifies the recency of the change, from 1 (new) to 10 (old). This is calculated as a 2-quantile and determines the length of distance between the median age of all the changes in the file and the recency of the current range's change.", null: false
    end
  end
end
