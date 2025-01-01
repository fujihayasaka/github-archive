# typed: strict
# frozen_string_literal: true

module Restorables
  # Public: Interface for subscription details of repositories watched with "All activity" or "ignore" settings. This
  # is used for methods used to persist Restorable::WatchedRepository records. It's implemented by Repositories
  # extended with the Restorables::SubscriptionDetails module and by the concrete WatchedRepositorySubscription
  # class.
  module IWatchedRepositorySubscription
    extend T::Helpers

    interface!

    # The repository's ID
    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    # Whether the repository subscription is ignored
    sig { abstract.returns(T.nilable(T::Boolean)) }
    def ignored; end

    # The ID of the user who is the subscriber (when feature flag enabled)
    sig { abstract.returns(T.nilable(Integer)) }
    def subscriber_id; end

    # The timestamp when the subscription was created (when feature flag enabled)
    sig { abstract.returns(T.nilable(Time)) }
    def subscribed_at; end
  end
end
