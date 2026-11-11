# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TeamDiscussionComment < Platform::Objects::Base
      model_name "DiscussionPostReply"
      description "A comment on a team discussion."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, comment)
        comment.async_organization.then do |org|
          permission.access_allowed?(
            :show_team_discussion_comment,
            resource: comment,
            organization: org,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_discussion_post.then { |discussion| permission.typed_can_see?("TeamDiscussion", discussion) }
      end

      minimum_accepted_scopes ["read:discussion"]

      required_capabilities [:mobile_only_schema_mask]

      # This is deliberately stripped down to nothing as this object only exists to keep old versions of the mobile apps working.
      # Team discussions have been deprecated since May '23 and not actually used anymore.
      field :id, ID, null: true
      field :url, Scalars::URI, null: true
    end
  end
end
