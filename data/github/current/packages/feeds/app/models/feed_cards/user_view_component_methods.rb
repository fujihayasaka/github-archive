# typed: strict
# frozen_string_literal: true

module FeedCards
  module UserViewComponentMethods
    include GitHub::Memoizer
    include FeedCards::ViewComponentMethods
    extend T::Helpers
    requires_ancestor { ApplicationComponent }
    abstract!

    private

    sig { returns(User) }
    memoize def user
      display_subject
    end

    sig { returns(String) }
    def user_name
      user.profile_name || user.display_login
    end

    sig { returns(Integer) }
    memoize def user_repo_count
      user.public_repository_count
    end

    sig { returns(Integer) }
    memoize def user_follower_count
      user.followers_count(viewer: current_user)
    end

    sig { returns(T.nilable(String)) }
    memoize def description
      if sponsored_action?
        user.sponsors_bio_html
      else
        user.profile_bio_html
      end
    end

    sig { returns(T::Boolean) }
    memoize def sponsoring?
      user.sponsored_by_viewer?(current_user)
    end

    sig { returns(T::Boolean) }
    def render_description?
      description.present?
    end

    sig { returns(T::Boolean) }
    def render_counts?
      return false if sponsored_action? && !subject_is_current_user?
      render_repo_count? || render_follower_count?
    end

    sig { returns(T::Boolean) }
    def render_repo_count?
      user_repo_count > 0
    end

    sig { returns(T::Boolean) }
    def render_follower_count?
      user_follower_count > 0
    end

    sig { returns(T::Boolean) }
    def render_sponsor_button?
      sponsored_action? && user.sponsorable?
    end

    sig { returns(T::Boolean) }
    def followed_action?
      item.followed_action?
    end

    sig { returns(T::Boolean) }
    def sponsored_action?
      item.sponsored_action?
    end

    sig { returns(T::Boolean) }
    def subject_is_current_user?
      return false unless logged_in?

      item.subject.id == current_user.id
    end

    sig { returns(T.untyped) }
    memoize def sponsors_listing
      user.sponsors_listing
    end

    sig { returns(T.untyped) }
    memoize def sponsors_goal
      sponsors_listing.active_goal
    end

    sig { params(click_target: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
    def hydro_data(click_target:)
      helpers.feed_clicks_hydro_attrs(click_target: click_target, feed_item: item)
    end
  end
end
