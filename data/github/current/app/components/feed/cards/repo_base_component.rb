# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class RepoBaseComponent < BaseComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      private

      def render?
        repository.present?
      end

      def actor
        item.actor
      end

      def timestamp
        repo_recommendation_event? ? nil : item.created_at
      end

      def action
        repo_recommendation_event? ? nil : item.action_string
      end

      def repo_recommendation_event?
        item.is_a?(Conduit::FeedItem::RepositoryRecommendation)
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

      def repo_recommendation_icon
        case item.reason
        when "followed"
          :flame
        when "topics"
          :telescope
        else
          :star
        end
      end

      def link_to_repo_recommendation
        case item.reason
        when "trending"
          render(Primer::Beta::Link.new(
            href: trending_index_path,
            scheme: :primary,
            underline: false,
            data: helpers.feed_clicks_hydro_attrs(click_target: "trending", feed_item: item)
          )) { "GitHub" }
        when "topics"
          render(Primer::Beta::Link.new(
            href: users_stars_topics_path(user: current_user, filter: "topics"),
            scheme: :primary,
            underline: false,
            data: helpers.feed_clicks_hydro_attrs(click_target: "topics", feed_item: item)
          )) { "your topics" }
        when "followed"
          render(Primer::Beta::Link.new(
            href: "#{user_path(current_user)}?tab=following",
            scheme: :primary,
            underline: false,
            data: helpers.feed_clicks_hydro_attrs(click_target: "following", feed_item: item)
          )) { "people you follow" }
        end
      end

      def owner_is_viewer?
        item.repository.owner&.id == item.viewer&.id
      end

      def parent_owner_is_viewer?
        item.repository&.parent&.owner&.id == item.viewer&.id
      end
    end
  end
end
