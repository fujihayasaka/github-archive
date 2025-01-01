# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteLinkedBranch < Platform::Mutations::Base
      include Helpers::GitRefs

      description "Unlink a branch from an issue."
      minimum_accepted_scopes ["public_repo"]

      argument :linked_branch_id, ID, "The ID of the linked branch", required: true, loads: Objects::LinkedBranch, as: :linked_branch

      field :issue, Objects::Issue, "The issue the linked branch was unlinked from.", null: true
      error_fields

      def resolve(linked_branch:, **inputs)
        issue = linked_branch.issue

        linked_branch.destroy

        if linked_branch.destroyed?
          return {
            issue: issue,
            errors: []
          }
        end

        raise Platform::Errors::Unprocessable.new("An error occured when unlinking the branch from the issue.")
      end

      def self.async_api_can_modify?(permission, linked_branch:, **inputs)
        permission.async_owner_if_org(linked_branch.issue_repository).then do |org|
          linked_branch.branch_repository.resources.contents.readable_by?(permission.viewer) && permission.access_allowed?(:edit_issue,
            resource: linked_branch.issue,
            repo: linked_branch.issue_repository,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end
    end
  end
end
