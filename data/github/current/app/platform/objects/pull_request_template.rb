# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestTemplate < Platform::Objects::Base
      description "A repository pull request template."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, template)
        permission.async_repo_and_org_owner(template).then do |repo, org|
          permission.access_allowed?(
            :list_issue_templates,    # use the same permission as issue templates
            resource: repo,
            current_repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end


      minimum_accepted_scopes ["repo"]

      field :repository, Objects::Repository, "The repository the template belongs to", null: false, method: :async_repository
      field :filename, String, "The filename of the template", null: true
      field :body, String, "The body of the template", null: true
    end
  end
end
