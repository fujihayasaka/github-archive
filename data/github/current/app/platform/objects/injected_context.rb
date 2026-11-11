# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class InjectedContext < Platform::Objects::Base
      description "Additional path and line numbers loaded with the diff as context lines"

      field :path, String, "File path included in the injected context", null: false
      field :start_line, Integer, "The starting line number of the injected context.", null: false
      field :end_line, Integer, "The ending line number of the injected context.", null: false

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        # To access this non Active Record object the caller already need to get permissions for a repo and a commit
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # To access this non Active Record object the caller already need to get permissions for a repo and a commit
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end
    end
  end
end
