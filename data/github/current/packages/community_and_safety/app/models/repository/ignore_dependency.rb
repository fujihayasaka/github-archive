# typed: false
# frozen_string_literal: true

module Repository::IgnoreDependency
  extend ActiveSupport::Concern

  # Public: Is this repository's owner blocking the specified user?
  #
  # user - a User or nil
  #
  # Returns a Boolean.
  def owner_blocking?(user)
    if user.nil? || user.id == owner_id
      false
    else
      @owner_blocking_by_user_id ||= {}
      return @owner_blocking_by_user_id[user.id] if @owner_blocking_by_user_id.key?(user.id)
      @owner_blocking_by_user_id[user.id] = user.blocked_by?(owner_id)
    end
  end

  # Public: Check if the given user is blocked from commenting on the given commentable record that's in this
  # repository.
  #
  # user - a User or nil
  # commentable - a Discussion, Issue, PullRequest, or other record that is part of this repository
  # user_can_push - optional Boolean to indicate whether the given user has access to push to this repository, if
  #                 already known; if nil is passed, the actual value will be looked up
  #
  # Returns a Boolean.
  def blocked_from_commenting?(user:, commentable:, user_can_push: nil)
    return false if private?
    return false if commentable.nil?
    if user_can_push.nil?
      user_can_push = pushable_by?(user)
    end
    return false if user_can_push
    owner_blocking?(user) || (user && user.blocked_by?(commentable.user))
  end
end
