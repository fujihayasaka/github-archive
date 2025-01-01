# typed: true
# frozen_string_literal: true

class WatchedRepositories
  module SubscriptionDetails
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
    # repositories - an Enumberable collection of Repositories
    # subscriptions - an Enumberable collection of Subscriptions
    # include_non_subscribed - a Boolean indicating whether the returned
    # collection should not be filtered so only repositories with subscriptions
    # are returned. Defaults to false.
    #
    # returns an Array of Repositories
    def self.decorate_collection(repositories, subscriptions: [], include_non_subscribed: false)
      return [] if repositories.empty?
      return [] if subscriptions.empty? && include_non_subscribed == false

      subscriptions_table = subscriptions.each_with_object({}) do |sub, subs|
        subs[sub.list_id] = sub.ignored?
      end

      decorated_collection = repositories.map do |repository|
        repository.extend(self)
        subscription_is_ignored = subscriptions_table[repository.id]
        repository.ignored = subscription_is_ignored
        repository
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

    def ignored=(value)
      @ignored = value
    end

    def ignored
      @ignored
    end
  end
end
