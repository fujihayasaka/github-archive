# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class DiscussionCategorySerializer < BaseSerializer
      def scope
        DiscussionCategory.preload(included_discussion_category_associations)
      end

      def as_json(options = {})
        {
          type: "discussion_category",
          url: url,
          repository: repository,
          name: discussion_category.name,
          emoji: discussion_category.emoji,
          description: discussion_category.description,
        }
      end

      private

      def discussion_category
        model
      end

      def included_discussion_category_associations
        [:repository]
      end

      def repository
        url_for_model(discussion_category.repository)
      end
    end
  end
end
