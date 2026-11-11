# typed: strict
# frozen_string_literal: true

module Restorables
  # Public: A plain Ruby object container for watched repository thread data.
  # This class provides a public interface for passing watched repository
  # thread information to the Restorable::WatchedRepositoryThread.backup method.
  #
  # Examples:
  #
  #   thread = Restorables::WatchedRepositoryThreadSubscription.new(
  #     user_id: 123,
  #     ignored: false,
  #     reason: "team_mention",
  #     thread_key: "Issue;123"
  #   )
  class WatchedRepositoryThreadSubscription
    # The ID of the user who owns this thread
    sig { returns(Integer) }
    attr_accessor :user_id

    # Whether the thread is ignored
    sig { returns(T::Boolean) }
    attr_accessor :ignored

    # The reason for the thread state (e.g., "mention", "author")
    sig { returns(T.nilable(String)) }
    attr_accessor :reason

    # The unique key identifying the thread
    sig { returns(String) }
    attr_accessor :thread_key

    sig do
      params(
        user_id: Integer,
        ignored: T::Boolean,
        reason: T.nilable(String),
        thread_key: String
      ).void
    end
    def initialize(user_id:, ignored:, reason:, thread_key:)
      @user_id = user_id
      @ignored = ignored
      @reason = reason
      @thread_key = thread_key
    end
  end
end
