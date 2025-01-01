# typed: strict
# frozen_string_literal: true

module Restorables
  module SubscriptionDetails
    extend T::Helpers
    include Restorables::IWatchedRepositorySubscription

    requires_ancestor { Repositories::IRepository }

    # Public: Decorates each Repository in REPOSITORIES with behavior defined
    # in SubscriptionDetails.
    #
    # If passed SUBSCRIPTIONS, will additionally set the `ignored?` value of
    # each Repository to the `ignored?` value of its corresponding subscription.
    #
    # A Repository object should respond to `ignored?` with `true` if the
    # repository's corresponding subscription is being `ignored?`, with `false`
    # if it is being watched, and with `nil` if neither.
    #
    # A Repository object will also respond to `subscriber_id` with the ID of
    # the user who is the subscriber, and to `subscribed_at` with the timestamp
    # when the subscription was created.
    #
    # repositories - an Enumberable collection of Repositories
    # subscriptions - an Enumberable collection of Subscriptions
    # include_non_subscribed - a Boolean indicating whether the returned
    # collection should not be filtered so only repositories with subscriptions
    # are returned. Defaults to false.
    # subscriber_id - The ID of the user who is the subscriber for these repositories
    #
    # returns an Array of Repositories
    sig do
      params(
        repositories: T::Array[Repositories::IRepository],
        subscriptions: T.untyped, # Newsies array of Subscription objects
        include_non_subscribed: T::Boolean,
        subscriber_id: T.nilable(Integer),
      ).returns(T::Array[SubscriptionDetails])
    end
    def self.decorate_collection(repositories, subscriptions: [], include_non_subscribed: false, subscriber_id: nil)
      return [] if repositories.empty?
      return [] if subscriptions.empty? && include_non_subscribed == false

      subscriptions_table = subscriptions.each_with_object({}) do |sub, subs|
        subs[sub.list_id] = {
          ignored: sub.ignored?,
          subscribed_at: sub.created_at
        }
      end

      decorated_collection = repositories.map do |repository|
        decorated_repo = T.cast(repository.extend(self), SubscriptionDetails)
        subscription_data = subscriptions_table[decorated_repo.id]

        decorated_repo.ignored = subscription_data&.dig(:ignored)
        decorated_repo.subscribed_at = subscription_data&.dig(:subscribed_at)
        decorated_repo.subscriber_id = subscriber_id if subscription_data

        decorated_repo
      end

      case include_non_subscribed
      when true
        decorated_collection
      when false
        decorated_collection.reject { |repo| repo.ignored.nil? }
      else
        raise ArgumentError, "include_non_subscribed: must be a Boolean"
      end
    end

    # Override to indicate that the id method provided by the IRepository ancestor satisfies the interface.
    sig { override.returns(T.nilable(Integer)) }
    def id
      super
    end

    sig { params(value: T.nilable(T::Boolean)).void }
    def ignored=(value)
      @ignored = T.let(value, T.nilable(T::Boolean))
    end

    sig { override.returns(T.nilable(T::Boolean)) }
    def ignored
      @ignored
    end

    sig { params(value: T.nilable(Integer)).void }
    def subscriber_id=(value)
      @subscriber_id = T.let(value, T.nilable(Integer))
    end

    sig { override.returns(T.nilable(Integer)) }
    def subscriber_id
      @subscriber_id
    end

    sig { params(value: T.nilable(Time)).void }
    def subscribed_at=(value)
      @subscribed_at = T.let(value, T.nilable(Time))
    end

    sig { override.returns(T.nilable(Time)) }
    def subscribed_at
      @subscribed_at
    end
  end
end
