# typed: true
# frozen_string_literal: true

class Profiles::User::MutualFollowersComponent < ApplicationComponent
  include AvatarHelper

  MUTUAL_FOLLOWERS_LIMIT = 1000

  attr_reader :user, :current_user

  sig { params(user: User, current_user: T.nilable(User)).void }
  def initialize(user:, current_user:)
    @user = user
    @current_user = current_user
  end

  sig { returns(T::Boolean) }
  def render?
    return false if GitHub.enterprise?
    return false if current_user.nil?
    return false if user == current_user
    return false if !user_or_global_feature_enabled?(:mutual_followers)
    return false if mutual_followers_count < 1

    true
  end

  private

  sig { returns(Integer) }
  memoize def mutual_followers_count
    Following.mutual_followers_count(user: user, viewer: current_user)
  end

  sig { returns(String) }
  def mutual_followers_display_count_label
    count = capped_number_with_delimiter(mutual_followers_count - 1, limit: MUTUAL_FOLLOWERS_LIMIT)
    "and #{count} more"
  end

  sig { returns(User) }
  def mutual_follower_example
    mutual_followers.first
  end

  sig { returns(ActiveRecord::Relation) }
  memoize def mutual_followers
    Following.mutual_followers(user: user, viewer: current_user).reorder("followers.created_at DESC")
  end

  sig { returns(String) }
  def url_to_followers
    "#{h(user_path(user))}?tab=followers"
  end

  sig { returns(String) }
  def hydro_tracking_label
    "current_user_id:#{current_user&.id};logged_in:true;user:#{user.id}"
  end
end
