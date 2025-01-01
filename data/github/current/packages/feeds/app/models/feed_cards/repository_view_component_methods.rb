# typed: strict
# frozen_string_literal: true

module FeedCards
  module RepositoryViewComponentMethods
    include GitHub::Memoizer
    include FeedCards::ViewComponentMethods
    extend T::Helpers
    requires_ancestor { ApplicationComponent }
    abstract!

    private

    sig { returns(T::Boolean) }
    def render?
      repository.present?
    end

    sig { returns(User) }
    memoize def actor
      item.actor
    end

    sig { returns(T.nilable(T.any(Time, ActiveSupport::TimeWithZone))) }
    def timestamp
      repo_recommendation_event? ? nil : item.created_at
    end

    sig { returns(String) }
    def action
      repo_recommendation_event? ? nil : item.action_string
    end

    sig { returns(T::Boolean) }
    def repo_recommendation_event?
      item.is_a?(Conduit::FeedItem::RepositoryRecommendation)
    end

    sig { returns(T.untyped) }
    def repository
      item.repository
    end

    sig { returns(T::Boolean) }
    memoize def repo_has_details?
      repository.stargazer_count > 0 ||
      repository.primary_language_name.present?
    end

    sig { returns(T::Boolean) }
    def include_star_button?
      repository.owner.present?
    end

    sig { returns(Symbol) }
    memoize def repo_recommendation_icon
      case item.reason
      when "followed"
        :flame
      when "topics"
        :telescope
      else
        :star
      end
    end

    sig { returns(T.untyped) }
    memoize def link_to_repo_recommendation
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

    sig { returns(T::Boolean) }
    memoize def owner_is_viewer?
      item.repository.owner&.id == item.viewer&.id
    end

    sig { returns(T::Boolean) }
    memoize def parent_owner_is_viewer?
      item.repository&.parent&.owner&.id == item.viewer&.id
    end
  end
end
