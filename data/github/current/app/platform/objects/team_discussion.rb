# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TeamDiscussion < Platform::Objects::Base
      model_name "DiscussionPost"
      description "A team discussion."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, discussion)
        discussion.async_organization.then do |org|
          permission.access_allowed?(
            :show_team_discussion,
            resource: discussion,
            organization: org,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_readable_by?(permission.viewer)
      end

      minimum_accepted_scopes ["read:discussion"]

      required_capabilities [:mobile_only_schema_mask]

      # This is deliberably stripped down to nothing as this object only exists to keep old versions of the mobile apps
      # working prior to https://github.com/github/mobile-android/pull/17048 and https://github.com/github/mobile-ios/pull/23150
      # Team discussions have been deprecated since May '23 and not used anymore.
      field :id, Integer, null: true
      field :url, Scalars::URI, null: true
      field :team, Objects::Team, null: true
    end
  end
end
