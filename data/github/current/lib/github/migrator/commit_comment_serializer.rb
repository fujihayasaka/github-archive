# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class CommitCommentSerializer < BaseSerializer
      def as_json(options = {})
        {
          type: "commit_comment",
          url: url,
          repository: repository,
          user: user,
          body: body,
          formatter: formatter,
          path: path,
          position: position,
          commit_id: commit_id,
          reactions: reactions,
          created_at: created_at,
        }
      end

      private

      def repository
        url_for_model(model.repository)
      end

      def user
        url_for_model(model.user)
      end

      def body
        model.body
      end

      def formatter
        model.formatter
      end

      def path
        model.path
      end

      def position
        model.position
      end

      def commit_id
        model.commit_id
      end

      def reactions
        model.reactions.map do |reaction|
          {
            user: url_for_model(reaction.user),
            content: reaction.content,
            subject_type: reaction.subject_type,
            created_at: reaction.created_at
          }
        end
      end
    end
  end
end
