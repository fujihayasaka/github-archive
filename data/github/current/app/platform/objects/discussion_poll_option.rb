# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DiscussionPollOption < Platform::Objects::Base
      description "An option for a discussion poll."
      scopeless_tokens_as_minimum

      visibility :public, environments: [:dotcom, :enterprise]

      implements_node templates: [[:rdpo, :repo_id, :discussion_id, :discussion_poll_option_id]], as: "DPO", ready_date: "1970-01-01" do |option|
        option.async_poll.then do |poll|
          poll.async_discussion.then do |discussion|
            {
              prefix: :rdpo,
              repo_id: discussion.repository_id,
              discussion_id: discussion.id,
              discussion_poll_option_id: option.id,
            }
          end
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, option)
        option.async_poll.then do |poll|
          poll.async_discussion.then do |discussion|
            permission.async_repo_and_org_owner(discussion).then do |repo, org|
              permission.access_allowed?(
                :show_discussion,
                resource: discussion,
                current_org: org,
                repo: repo,
                allow_integrations: true,
                allow_user_via_granular_actor: true,
              )
            end
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, option)
        # For GitHub Apps, we'll rely on `async_api_can_access?` to gate
        # permission to view a Discussion, as long as the app has access
        # to the repository the Discussion is in. We have to do this to make
        # sure we return the correct errors for an App that doesn't have the
        # correct permissions. See https://github.com/github/discussions/issues/1567.
        option.async_poll.then do |poll|
          poll.async_discussion.then do |discussion|
            if permission.viewer&.can_have_granular_permissions?
              permission.belongs_to_repository(discussion)
            else
              discussion.async_readable_by?(permission.viewer)
            end
          end
        end
      end

      field :option,
        String,
        description: "The text for this option.",
        null: false

      field :total_vote_count,
        Integer,
        description: "The total number of votes that have been cast for this option.",
        method: :discussion_poll_votes_count,
        null: false

      field :viewer_has_voted,
        Boolean,
        description: "Indicates if the viewer has voted for this option in the poll.",
        null: false

      def viewer_has_voted
        @object.has_voted?(context[:viewer])
      end

      field :poll,
        Objects::DiscussionPoll,
        description: "The discussion poll that this option belongs to.",
        method: :async_poll,
        null: true
    end
  end
end
