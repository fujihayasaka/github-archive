# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class FollowRecommendationComponent < ApplicationComponent
      include GitHub::Memoizer
      include FeedCards::ViewComponentMethods

      private

      def render?
        item.present?
      end

      # we don't want to render timestamps for this card
      def timestamp
        nil
      end

      memoize def follow_items
        [item, *item.related_items].compact
      end

      def col_class
        return unless follow_items.size > 1
        "col-xl-6"
      end
    end
  end
end
