# typed: true
# frozen_string_literal: true

module Newsies
  # Public: Subscriber is responsible for specifying a User that has subscribed to a List or
  # Thread.
  class Subscriber
    attr_accessor :user_id, :is_valid, :is_ignored, :reason, :created_at, :events

    # Public: Sets a full User object if available.  Should match #user_id.
    attr_writer :user

    # this include _has_ to be after the attr_accessor declaration because it
    # needs access to those accessors as it is being mixed in
    include CommonSubscriptionHelper

    def initialize(user_id = nil, is_valid = nil, is_ignored = nil, reason = nil, created_at = nil, events = [])
      @user_id    = user_id
      @is_valid   = is_valid
      @is_ignored = is_ignored
      @reason     = reason
      @created_at = created_at
      @events = events
    end

    # Public: Returns a full User object if available.  Should match #user_id.
    def user
      @user
    end

    def ==(other)
      other.is_a?(self.class) && other.user_id == user_id
    end

    def to_i
      user_id
    end

    def inspect
      build_inspect "user=##{user_id},"
    end
  end
end
