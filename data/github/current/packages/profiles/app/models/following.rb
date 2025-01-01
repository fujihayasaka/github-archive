# typed: false
# frozen_string_literal: true

class Following < ApplicationRecord::Domain::Users
  include Instrumentation::Model
  include Spam::Spammable
  include GitHub::RateLimitedCreation

  self.table_name = "followers"

  # follower
  belongs_to :user

  # followee
  belongs_to :following, class_name: "User"

  setup_spammable(:user)

  after_commit :instrument_create, on: :create
  after_commit :instrument_destroy, on: :destroy

  validates :user_id, uniqueness: { scope: [:following_id] }

  # Public: Follows where the given User (or User ID) is being followed.
  #
  # user - a User or Integer ID
  #
  # Returns Followings.
  scope :follower_of, ->(user) { where(following_id: user) }

  # Public: Follows where the given User (or User ID) is the one doing the following.
  #
  # user - a User or Integer ID
  #
  # Returns Followings.
  scope :followed_by, ->(user) { where(user_id: user) }

  # Public: Follows where the given User (or User ID) is either being followed or doing the
  # following.
  #
  # user - a User or Integer ID
  #
  # Returns Followings.
  scope :involving, ->(user) do
    where("followers.user_id = ? OR followers.following_id = ?", user, user)
  end

  scope :join_follower_users, -> do
    joins("INNER JOIN users follower_users " \
          "ON follower_users.id = #{table_name}.user_id")
  end

  # Public: Join to the users table, aliased as "followed_users", using the followed user foreign
  # key (following_id).
  #
  # Returns an ActiveRecord Relation.
  scope :join_followed_users, -> do
    joins("INNER JOIN users followed_users " \
          "ON followed_users.id = #{table_name}.following_id")
  end

  # Public: Filter out followings where the follower or followed user is spammy.
  #
  # viewer - a User or nil
  # type - a Symbol:
  #        :follower - returned Followings will include those where the given User is the one being
  #                    followed
  #        :followed_user - returned Followings will include those where the given User is the
  #                         follower
  #
  # Returns Followings.
  scope :filter_spammy_followers_and_followed_users, ->(viewer, type:) do
    followings = self

    if viewer.nil? || !viewer.site_admin?
      if type == :follower
        followings = followings.join_follower_users.where("follower_users.spammy = ?", false)
      elsif type == :followed_user
        followings = followings.join_followed_users.where("followed_users.spammy = ?", false)
      end
    end

    followings
  end

  # Public: Exclude suspended followers and suspended followed users.
  #
  # type - a Symbol:
  #        :follower - returned Followings will include those where the given User is the one being
  #                    followed
  #        :followed_user - returned Followings will include those where the given User is the
  #                         follower
  #
  # Returns Followings.
  scope :not_suspended, ->(type:) do
    followings = self

    if type == :follower
      followings = followings.join_follower_users.where("follower_users.suspended_at IS NULL")
    elsif type == :followed_user
      followings = followings.join_followed_users.where("followed_users.suspended_at IS NULL")
    end

    followings
  end

  # Public: Filter out followers that are organizations
  #
  # viewer - a User or nil
  #
  # Returns Followings
  scope :not_organizations, ->(type:) do
    followings = self

    if type == :follower
      followings = followings.join_follower_users.where("follower_users.type != ?", "Organization")
    elsif type == :followed_user
      followings = followings.join_followed_users.where("followed_users.type != ?", "Organization")
    end

    followings
  end

  private

  def event_payload
    {
      follower: user.to_s,
      follower_id: user.id,
      followee: following.to_s,
      followee_id: following.id,
      followee_type: following.type
    }
  end

  def instrument_create
    hydro_payload = {
      actor: user,
      followee: following,
      followed_at: created_at,
    }

    GlobalInstrumenter.instrument "user.follow", hydro_payload

    instrument :create
  end

  def instrument_destroy
    hydro_payload = {
      actor: user,
      followee: following,
      unfollowed_at: Time.current,
      followee_id: following_id
    }

    GlobalInstrumenter.instrument "user.unfollow", hydro_payload
  end

  # Custom set_user_hidden method for Followings to handle both the user and
  # the following being spammy.
  #
  # we have to set the integer value so we don't update this unnecessarily
  # see https://github.com/github/github/pull/204652/files#r778329972
  def set_user_hidden
    self.user_hidden = (user&.content_hidden? || following&.content_hidden?) ? 1 : 0
  end
end
