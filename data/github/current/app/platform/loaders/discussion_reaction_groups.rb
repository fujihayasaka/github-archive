# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class DiscussionReactionGroups < Platform::Loader
      def self.load(discussion)
        self.for.load(discussion)
      end

      def fetch(discussions)
        reactions = DiscussionReaction.find_by_sql(build_reactions_query(discussions: discussions))

        grouped_reactions = reactions.group_by do |reaction|
          [reaction.discussion_id, reaction.content]
        end

        discussion_with_reaction_groups = discussions.map do |discussion|
          reaction_groups = ::Emotion.all.map do |emotion|
            ::Discussion::ReactionGroup.new(
              subject: discussion,
              emotion: emotion,
              reactions: grouped_reactions[[discussion.id, emotion.content]] || [],
            )
          end

          [discussion, reaction_groups]
        end

        discussion_with_reaction_groups.to_h
      end

      def build_reactions_query(discussions:)
        reactions_sql = Arel.sql(<<~SQL, discussion_ids: discussions.map(&:id))
            SELECT id, discussion_id, content, user_id, created_at
            FROM discussion_reactions
            WHERE discussion_id IN (:discussion_ids)
          SQL

        if GitHub.spamminess_check_enabled?
          reactions_sql += Arel.sql(<<~SQL)
            AND user_hidden = false
          SQL
        end

        reactions_sql += Arel.sql(<<~SQL)
          ORDER BY discussion_id, user_hidden, created_at, id
        SQL

        reactions_sql
      end
    end
  end
end
