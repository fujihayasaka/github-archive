# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryCodeownersError < Platform::Objects::Base
      description "An error in a `CODEOWNERS` file."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        permission.access_allowed?(
          :get_contents,
          resource: object.repository,
          current_repo: nil,
          current_org: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: true,
        )
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("Repository", object.repository)
      end

      scopeless_tokens_as_minimum

      field :kind, String, description: "A short string describing the type of error.", null: false
      field :line, Integer, description: "The line number where the error occurs.", null: false
      field :column, Integer, description: "The column number where the error occurs.", null: false
      field :source, String, description: "The content of the line where the error occurs.", null: false
      field :suggestion, String, description: "A suggestion of how to fix the error.", null: true
      field :message, String, description: "A complete description of the error, combining information from other fields.", null: false
      field :path, String, description: "The path to the file when the error occurs.", null: false
    end
  end
end
