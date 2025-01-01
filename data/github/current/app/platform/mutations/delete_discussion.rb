# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteDiscussion < Platform::Mutations::Base
      description "Delete a discussion and all of its replies."

      minimum_accepted_scopes ["public_repo"]

      argument :id, ID, "The id of the discussion to delete.", required: true,
        loads: Objects::Discussion, as: :discussion

      field :discussion, Objects::Discussion, "The discussion that was just deleted.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, discussion:, **inputs)
        permission.async_repo_and_org_owner(discussion).then do |repo, org|
          permission.access_allowed?(
            :delete_discussion,
            repo: repo,
            current_org: org,
            resource: discussion,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(discussion:, **inputs)
        deleter = ::DiscussionDeleter.new(discussion)

        actor = context[:actor].try(:can_have_granular_permissions?) ? context[:actor].bot : context[:actor]
        if deleter.delete(actor)
          { discussion: discussion }
        else
          raise Errors::Unprocessable.new("Could not delete discussion.")
        end
      end
    end
  end
end
