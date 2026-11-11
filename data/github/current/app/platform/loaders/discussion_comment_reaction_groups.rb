# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class DiscussionCommentReactionGroups < Platform::Loader
      def self.load(discussion_comment)
        self.for.load(discussion_comment)
      end

      def fetch(discussion_comments)
        reactions = DiscussionCommentReaction.find_by_sql(build_reactions_query(
          discussion_comments: discussion_comments
        ))

        grouped_reactions = reactions.group_by do |reaction|
          [reaction.discussion_comment_id, reaction.content]
        end

        discussion_comments_with_reaction_groups = discussion_comments.map do |discussion_comment|
          reaction_groups = ::Emotion.all.map do |emotion|
            ::Discussion::ReactionGroup.new(
              subject: discussion_comment,
              emotion: emotion,
              reactions: grouped_reactions[[discussion_comment.id, emotion.content]] || [],
            )
          end

          [discussion_comment, reaction_groups]
        end

        discussion_comments_with_reaction_groups.to_h
      end

      def build_reactions_query(discussion_comments:)
        reactions_sql = Arel.sql(<<~SQL, discussion_comment_ids: discussion_comments.map(&:id))
            SELECT id, discussion_comment_id, content, user_id, created_at
            FROM discussion_comment_reactions
            WHERE discussion_comment_id IN (:discussion_comment_ids)
          SQL

        if GitHub.spamminess_check_enabled?
          reactions_sql += Arel.sql(<<~SQL)
            AND user_hidden = false
          SQL
        end

        reactions_sql += Arel.sql(<<~SQL)
          ORDER BY discussion_comment_id, user_hidden, created_at, id
        SQL

        reactions_sql
      end
    end
  end
end
