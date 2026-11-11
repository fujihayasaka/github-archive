# typed: strict
# frozen_string_literal: true

module Restorables
  # Public: A plain Ruby object container for custom watched repository subscription data.
  # This class provides a public interface for passing custom watched repository
  # subscription information to the Restorable::CustomWatchedRepository.backup method.
  #
  # Examples:
  #
  #   subscription = Restorables::CustomWatchedRepositorySubscription.new(
  #     user_id: 123,
  #     thread_type: "Issue",
  #     original_created_at: Time.current
  #   )
  class CustomWatchedRepositorySubscription
    # The ID of the subscribing user
    sig { returns(Integer) }
    attr_accessor :user_id

    # The type of thread subscription (e.g., "RepositoryActivity")
    sig { returns(String) }
    attr_accessor :thread_type

    # The original creation timestamp of the subscription
    sig { returns(Time) }
    attr_accessor :original_created_at

    sig do
      params(
        user_id: Integer,
        thread_type: String,
        original_created_at: Time
      ).void
    end
    def initialize(user_id:, thread_type:, original_created_at:)
      @user_id = user_id
      @thread_type = thread_type
      @original_created_at = original_created_at
    end
  end
end
