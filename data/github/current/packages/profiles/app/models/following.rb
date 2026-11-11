# typed: false
# frozen_string_literal: true

class Following < ApplicationRecord::Domain::Users
  include Instrumentation::Model
  include Spam::Spammable
  include GitHub::RateLimitedCreation

  self.table_name = "followers"

  # follower
  include ::Users::BelongsToUser
  belongs_to_user_via_domain

  # followee
  belongs_to :following, class_name: "User"

  setup_spammable(:user)

  after_commit :instrument_create, on: :create
  after_commit :instrument_destroy, on: :destroy

  before_save :populate_following_type

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

  # Public: Filter to only followings where the followed entity is a User (excludes Organizations).
  #
  # Returns an ActiveRecord Relation.
  scope :only_followed_users, -> { where(following_type: "User") }

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

  def populate_following_type
    self.following_type = following&.type
  end
end
