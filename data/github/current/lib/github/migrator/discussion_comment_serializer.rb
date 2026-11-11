# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class DiscussionCommentSerializer < BaseSerializer
      def scope
        DiscussionComment.preload(included_discussion_comment_associations)
      end

      def as_json(options = {})
        {
          type: "discussion_comment",
          url: url,
          user: user,
          discussion: discussion,
          body: body,
          reactions: reactions,
          created_at: created_at,
          updated_at: updated_at,
          parent_comment: parent_comment,
        }
      end

      private

      def included_discussion_comment_associations
        [:user, :reactions, :discussion, :parent_comment]
      end

      def discussion_comment
        model
      end

      def discussion
        url_for_model(discussion_comment.discussion)
      end

      def user
        url_for_model(discussion_comment.user)
      end

      def parent_comment
        url_for_model(discussion_comment.parent_comment) if discussion_comment.nested?
      end

      def body
        discussion_comment.body
      end

      def reactions
        discussion_comment.reactions.map do |reaction|
          {
            user: url_for_model(reaction.user),
            content: reaction.content,
            subject_type: "Discussion",
            created_at: time(reaction.created_at)
          }
        end
      end
    end
  end
end
