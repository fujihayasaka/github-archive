# typed: strict
# frozen_string_literal: true

module Restorables
  # Public: Concrete implementation of IWatchedRepositorySubscription interface.
  #
  # This class provides a concrete implementation of the subscription details
  # needed for backup operations.
  class WatchedRepositorySubscription
    include IWatchedRepositorySubscription

    sig { params(id: Integer, ignored: T::Boolean, subscriber_id: Integer, subscribed_at: Time).void }
    def initialize(id:, ignored:, subscriber_id:, subscribed_at:)
      @id = id
      @ignored = ignored
      @subscriber_id = subscriber_id
      @subscribed_at = subscribed_at
    end

    # The repository's ID
    sig { override.returns(Integer) }
    def id
      @id
    end

    # Whether the repository subscription is ignored
    sig { override.returns(T::Boolean) }
    def ignored
      @ignored
    end

    # The ID of the user who is the subscriber
    sig { override.returns(Integer) }
    def subscriber_id
      @subscriber_id
    end

    # The timestamp when the subscription was created
    sig { override.returns(Time) }
    def subscribed_at
      @subscribed_at
    end
  end
end
