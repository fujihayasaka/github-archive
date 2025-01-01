# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class TrendingRepoComponent < ApplicationComponent
      include GitHub::Memoizer
      include FeedCards::ViewComponentMethods

      private

      def render?
        repository.present?
      end

      def actor
        item.actor
      end

      # trending repos will be displayed in a trending block rather than as an individual item,
      # therefore action string isn't neccesary.
      def action
        nil
      end

      def timestamp
        nil
      end

      def repository
        item.repository
      end

      def repo_has_details?
        repository.stargazer_count > 0 ||
        repository.primary_language_name.present?
      end

      def include_star_button?
        repository.owner.present?
      end
    end
  end
end
