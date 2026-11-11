# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PinnedDiscussion < Platform::Objects::Base
      description "A Pinned Discussion is a discussion pinned to a repository's index page."
      model_name "DiscussionSpotlight"
      scopeless_tokens_as_minimum

      implements_node templates: [[:rpid, :repo_id, :pinned_discussion_id]], as: "PID", ready_date: "2021-08-30" do |pinned_discussion|
        {
          prefix: :rpid,
          repo_id: pinned_discussion.repository_id,
          pinned_discussion_id: pinned_discussion.id
        }
      end

      implements Platform::Interfaces::RepositoryNode

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, discussion_spotlight)
        discussion_spotlight.async_discussion.then do |discussion|
          permission.async_repo_and_org_owner(discussion).then do |repo, org|
            permission.access_allowed?(
              :show_discussion,
              resource: discussion,
              repo: repo,
              current_org: org,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
              # Allow pinned discussions on public repos to be returned even when the current GitHub app isn't
              # installed on the repo.
              approved_integration_required: false,
            )
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, discussion_spotlight)
        discussion_spotlight.async_discussion.then do |discussion|
          discussion.async_readable_by?(permission.viewer)
        end
      end

      database_id_field
      created_at_field
      updated_at_field

      field :discussion, Objects::Discussion, method: :async_discussion, description: "The discussion that was pinned.", null: false
      field :pinned_by, Interfaces::Actor, method: :async_spotlighted_by, description: "The actor that pinned this discussion.", null: false

      field :pattern, Enums::PinnedDiscussionPattern, description: "Background texture pattern", null: false
      field :preconfigured_gradient, Enums::PinnedDiscussionGradient, description: "Preconfigured background gradient option", null: true, method: :api_preconfigured_color
      field :gradient_stop_colors, [String], description: "Color stops of the chosen gradient", null: false, method: :color_stops
    end
  end
end
