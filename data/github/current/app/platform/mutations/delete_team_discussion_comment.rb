# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteTeamDiscussionComment < Platform::Mutations::Base
      description "Deletes a team discussion comment."

      minimum_accepted_scopes ["write:discussion"]

      argument :id, ID, "The ID of the comment to delete.", required: true, loads: Objects::TeamDiscussionComment, as: :comment

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, comment:, **inputs)
        comment.async_organization.then do |org|
          permission.access_allowed?(
            :delete_team_discussion_comment,
            resource: comment,
            organization: org,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true)
        end
      end

      def resolve(comment:, **inputs)

        unless comment.async_viewer_can_delete?(context[:viewer]).sync
          message = "#{context[:viewer].display_login} does not have permission to delete the comment '#{comment.global_relay_id}'."
          raise Errors::Forbidden.new(message)
        end

        comment.destroy

        {}
      end
    end
  end
end
