# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class DiscussionSerializer < BaseSerializer
      def scope
        Discussion.preload(included_discussion_associations)
      end

      def as_json(options = {})
        {
          type: "discussion",
          url: url,
          repository: repository,
          user: user,
          title: title,
          body: body,
          labels: labels,
          reactions: reactions,
          created_at: created_at,
          updated_at: updated_at,
          discussion_category: discussion_category,
        }
      end

      private

      def included_discussion_associations
        [:repository, :user, :labels, :reactions]
      end

      def discussion
        model
      end

      def repository
        url_for_model(discussion.repository)
      end

      def user
        url_for_model(discussion.user)
      end

      def title
        discussion.title
      end

      def body
        discussion.body
      end

      def labels
        discussion.labels.map do |label|
          url_for_model(label)
        end
      end

      def reactions
        discussion.reactions.map do |reaction|
          {
            user: url_for_model(reaction.user),
            content: reaction.content,
            subject_type: "Discussion",
            created_at: time(reaction.created_at)
          }
        end
      end

      def discussion_category
        url_for_model(discussion.category)
      end
    end
  end
end
