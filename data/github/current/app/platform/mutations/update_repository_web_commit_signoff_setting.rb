# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateRepositoryWebCommitSignoffSetting < Platform::Mutations::Base
      description "Sets whether contributors are required to sign off on web-based commits for a repository."

      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The ID of the repository to update.", required: true,
        loads: Objects::Repository
      argument :web_commit_signoff_required, Boolean,
        "Indicates if the repository should require signoff on web-based commits.",
        required: true

      field :repository, Objects::Repository, "The updated repository.", null: true

      field :message, String, "A message confirming the result of updating the web commit signoff setting.", null: true

      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(:edit_repo,
            resource: repository,
            current_repo: repository,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(repository:, **inputs)
        viewer = context[:viewer]
        web_commit_signoff_required = inputs[:web_commit_signoff_required]

        if repository.owner&.organization? && repository.organization&.dco_signoff_enabled?
          raise Errors::Forbidden.new("Commit signoff is enforced by the organization and cannot be modified.")
        end

        unless repository.writable_by?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to update #{repository.name_with_display_owner}.")
        end

        unless repository.resources.administration.writable_by?(viewer)
          raise Errors::Unauthorized::Write,
            "#{viewer.display_login} does not have permission to update #{repository.name_with_display_owner}."
        end

        if web_commit_signoff_required
          repository.enable_dco_signoff(actor: viewer)
          message = "Web commit signoff is now enabled for #{repository.name}."
        else
          repository.reset_dco_signoff(actor: viewer)
          message = "Web commit signoff is now disabled for #{repository.name}."
        end

        {
          repository: repository,
          message: message,
        }
      end
    end
  end
end
