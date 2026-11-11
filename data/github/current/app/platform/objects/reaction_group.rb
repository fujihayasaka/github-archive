# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ReactionGroup < Platform::Objects::Base
      include Platform::Authorization::ReauthorizeScopedObjects

      # DiscussionReaction and DiscussionCommentReaction can be represented as a ReactionGroup,
      # however they are loaded differently. The reacting user ids are determined based on the
      # user_ids of the reactions.
      DISCUSSION_REACTIONS = %w(Discussion::ReactionGroup DiscussionComment::ReactionGroup)
      description "A group of emoji reactions to a particular piece of content."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, reaction_group)
        subject = reaction_group.subject

        permission.rewrite_reaction_subject(subject).then do |subject_type, subject|
          permission.typed_can_access?(subject_type, subject)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.rewrite_reaction_subject(object.subject).then do |subject_type, subject|
          permission.typed_can_see?(subject_type, subject)
        end
      end

      scopeless_tokens_as_minimum

      field :content, Enums::ReactionContent, "Identifies the emoji reaction.", null: false

      field :subject, Interfaces::Reactable, description: "The subject that was reacted to.", null: false

      def subject
        subject = @object.subject

        if subject.is_a?(::Issue)
          # It might be a PullRequest, let's check
          subject.async_pull_request.then { |pull| pull || subject }
        else
          subject
        end
      end

      field :created_at, Scalars::DateTime, "Identifies when the reaction was created.", null: true

      field :total_count, Integer, "Count of reactions for this reaction group", null: false, visibility: :internal

      def total_count
        @object.total_count
      end

      field :viewer_has_reacted, Boolean, description: "Whether or not the authenticated user has left a reaction on the subject.", null: false

      def viewer_has_reacted
        return @object.user_reacted?(@context[:viewer]) if DISCUSSION_REACTIONS.include? @object.class.name

        viewer = @context[:viewer]
        return false unless viewer
        return false if @object.total_count == 0
        Loaders::HasReacted.load(viewer.id, @object)
      end

      field :users, Connections::ReactingUser, description: "Users who have reacted to the reaction subject with the emotion represented by this reaction group", null: false, connection: true do
        deprecated(
          start_date: Date.new(2021, 5, 27),
          reason: "Reactors can now be mannequins, bots, and organizations.",
          superseded_by: "Use the `reactors` field instead.",
          owner: "synthead"
        )
      end

      def users
        if DISCUSSION_REACTIONS.include? @object.class.name
          return ArrayWrapper.new(@object.reactions.map(&:user_id))
        end

        if @object.total_count == 0
          # We already know from the group that there are no results
          ArrayWrapper.new([])
        else
          Loaders::ReactingUserIds.load(@object.subject, @object.content).then do |reactions|
            ArrayWrapper.new(reactions)
          end
        end
      end

      field :reactors, Connections::Reactor, description: "Reactors to the reaction subject with the emotion represented by this reaction group.", null: false, connection: true

      def reactors
        if DISCUSSION_REACTIONS.include? @object.class.name
          return ArrayWrapper.new(@object.reactions.map(&:user_id))
        end

        if @object.total_count == 0
          # We already know from the group that there are no results
          ArrayWrapper.new([])
        else
          Loaders::ReactingUserIds.load(@object.subject, @object.content).then do |reactions|
            ArrayWrapper.new(reactions)
          end
        end
      end
    end
  end
end
