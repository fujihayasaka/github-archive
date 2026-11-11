# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryCodeowners < Platform::Objects::Base
      description "Information extracted from a repository's `CODEOWNERS` file."

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

      field :errors, [Platform::Objects::RepositoryCodeownersError],
        description: "Any problems that were encountered while parsing the `CODEOWNERS` file.",
        connection: false,
        null: false

      def errors
        @object.repository.async_organization.then do
          errors = @object.errors + @object.owner_errors
          errors.sort_by!(&:line)

          errors.map do |error|
            Models::RepositoryCodeownersError.new(@object, error)
          end
        end
      end
    end
  end
end
