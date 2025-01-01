# typed: false
# frozen_string_literal: true

module Newsies

  # Responsible for querying the subscribers to a list and thread, and
  # ensuring they get the notifications they are signed up for.  A couple
  # rules:
  #
  # * If you ignore the thread or list, you won't get the notification.
  # * You only get one notification.
  class SubscriberSet
    attr_reader :subscribed, :ignored

    # list                 - An optional Newsies::List instance.
    # thread               - An optional Newsies::Thread instance.
    # explicit_subscribers - Optional list of people to be subscribed, that overwrite that fetched
    #                        from the list and thread subscription lists
    def initialize(list: nil, thread: nil, explicit_subscribers: nil)
      @list = if list
        list
      elsif thread
        thread.list
      end
      @thread = thread

      if explicit_subscribers
        build_sets_for_explicit_subscribers(explicit_subscribers)
      else
        build_sets_for_all_subscribers
      end
    end

    # Public: Returns the list of subscribers for this set
    #
    # Each element in the list is a Newsies::Subscriber object
    #
    # Returns [Newsies::Subscriber]
    def subscribers
      subscribed.values
    end

    # Public: Checks to see if the given user ID is a member of this set.
    #
    # id - Integer user ID.
    #
    # Returns true if it's a member, or false.
    def subscribed?(id)
      subscribed.key?(id)
    end

    # Public: Checks to see if the given user ID is ignoring either the list
    # or thread of this set.
    #
    # id - Integer user ID
    #
    # Returns true if it's ignored, or false.
    def ignored?(id)
      ignored.include?(id)
    end

    def reason(id)
      return unless sub = subscribed[id]
      sub.reason
    end

    def inspect
      [
        "#<#{self.class.name}:#{object_id}",
        "@list=#{@list.inspect}",
        "@thread=#{@thread.inspect}",
        "@subscribed=#{(@subscribed.try(:keys) || []).inspect}",
        "@ignored=#{@ignored.inspect}>",
      ].join(" ")
    end

    private

    # Builds the @subscribed hash of { user_ids: Subscriber } by iterating over all
    # relevant list, thread type, and thread subscribers. Subscribers will only be kept
    # if they are not ignoring either the list or thread.
    #
    # The set of subscribed users is modeled as a Hash, where the keys are the
    # ids of the users that are subscribed, and the values are Newsies::Subscriber
    # objects. That way, when iterating the set, the yielded object will already contain
    # completed information about the subscriber.
    def build_sets_for_all_subscribers
      @ignored = Set.new
      @subscribed = {} # user_id => Subscriber

      if @thread
        ThreadSubscription.each(@thread) do |candidates|
          candidates.each { |candidate| handle_subscriber(candidate) }
        end

        ThreadTypeSubscription.for_list(@list).for_thread_type(@thread.subscription_type).find_each do |subscription|
          handle_subscriber(subscription.to_subscriber)
        end
      end

      if @list
        ListSubscription.each(@list) do |candidates|
          candidates.each { |candidate| handle_subscriber(candidate) }
        end
      end

      @subscribed.except!(*@ignored)
    end

    # Builds the @subscribed hash of { user_ids: Subscriber } for only
    # the passed explicit_subscribers
    #
    # We still must iterate over all existing subscribers at the list/thread level
    # to ensure that the explicit subscribers are not ignoring the list/thread.
    # For anyone ignoring the list/thread, we will not notify them even if they are
    # in explicit_subscribers.
    def build_sets_for_explicit_subscribers(explicit_subscribers)
      @ignored = Set.new
      @subscribed = {}

      explicit_subscribers.each do |sub|
        @subscribed[sub.user_id] = sub
      end

      if @list
        ListSubscription.each(@list) do |candidates|
          candidates.each do |sub|
            @ignored << sub.user_id if sub.ignored?
          end
        end
      end

      if @thread
        ThreadSubscription.each(@thread) do |candidates|
          candidates.each do |sub|
            @ignored << sub.user_id if sub.ignored?
          end
        end
      end

      @subscribed.except!(*@ignored)
    end

    # Adds subscribers to either the subscribed hash or the ignored set
    def handle_subscriber(subscriber)
      if subscriber.ignored?
        @ignored << subscriber.user_id
      else
        @subscribed[subscriber.user_id] ||= subscriber
      end
    end
  end # SubscriberSet

  class EmptySubscriberSet < SubscriberSet
    def initialize
      @ignored = Set.new.freeze
      @subscribed = Hash.new.freeze
    end

    def self.instance
      ::Thread.current["EmptySubscriberSet"] ||= new
    end
  end # EmptySubscriberSet
end
