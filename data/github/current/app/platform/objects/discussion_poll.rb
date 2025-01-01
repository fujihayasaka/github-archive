# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DiscussionPoll < Platform::Objects::Base
      description "A poll for a discussion."
      scopeless_tokens_as_minimum

      visibility :public, environments: [:dotcom, :enterprise]

      implements_node templates: [[:rdp, :repo_id, :discussion_id, :discussion_poll_id]], as: "DP", ready_date: "1970-01-01" do |poll|
        poll.async_discussion.then do |discussion|
          {
            prefix: :rdp,
            repo_id: discussion.repository_id,
            discussion_id: discussion.id,
            discussion_poll_id: poll.id,
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, poll)
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

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, poll)
        # For GitHub Apps, we'll rely on `async_api_can_access?` to gate
        # permission to view a Discussion, as long as the app has access
        # to the repository the Discussion is in. We have to do this to make
        # sure we return the correct errors for an App that doesn't have the
        # correct permissions. See https://github.com/github/discussions/issues/1567.
        poll.async_discussion.then do |discussion|
          if permission.viewer&.can_have_granular_permissions?
            permission.belongs_to_repository(discussion)
          else
            discussion.async_readable_by?(permission.viewer)
          end
        end
      end

      field :question,
        String,
        description: "The question that is being asked by this poll.",
        null: false

      field :total_vote_count,
        Integer,
        description: "The total number of votes that have been cast for this poll.",
        method: :discussion_poll_votes_count,
        null: false

      field :viewer_can_vote,
        Boolean,
        description: "Indicates if the viewer has permission to vote in this poll.",
        null: false

      sig { returns Promise[T::Boolean] }
      def viewer_can_vote
        @object.async_discussion.then do |discussion|
          discussion.async_poll_votable_by?(context[:viewer])
        end
      end

      field :viewer_has_voted,
        Boolean,
        description: "Indicates if the viewer has voted for any option in this poll.",
        null: false

      sig { returns T::Boolean }
      def viewer_has_voted
        @object.has_voted?(context[:viewer])
      end

      field :discussion,
        Objects::Discussion,
        description: "The discussion that this poll belongs to.",
        method: :async_discussion,
        null: true

      field :options,
        Connections.define(Objects::DiscussionPollOption),
        description: "The options for this poll.",
        connection: true,
        null: true do
        argument :order_by,
          Inputs::DiscussionPollOptionOrder,
          description: "How to order the options for the discussion poll.",
          required: false,
          default_value: { field: "id", direction: "ASC" }
      end

      def options(order_by:)
        @object.options.order("discussion_poll_options.#{order_by[:field]} #{order_by[:direction]}")
      end
    end
  end
end
