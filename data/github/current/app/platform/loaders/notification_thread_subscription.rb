# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class NotificationThreadSubscription < Platform::Loader
      # NotificationThreadSubscriptionResult
      #
      # Description:
      #
      # A decorator class that is used to return the results of a
      # subscription.
      #
      # Notes:
      #
      # We have two loaders that can return a result
      # this class gives us a common object to return the results
      # regardless of whether the result came from newsies or notifyd.
      class NotificationThreadSubscriptionResult
        attr_accessor :valid
        attr_accessor :ignored
        attr_reader :list, :thread
        alias_method :valid?, :valid
        alias_method :ignored?, :ignored

        def initialize(list:, thread:, valid: false, ignored: false)
          @list = list
          @thread = thread
          @valid = valid
          @ignored = ignored
        end
      end

      # ThreadDecorator
      #
      # Description:
      #
      # A decorator class that is used as the objects the loader provides to `fetch`
      # when called.
      #
      # Notes:
      #
      # This class allows us to isolate the newsies / notifyd logic from the loader itself.
      # The loader will simply call the #managed_by_notifyd? method to partition and then use
      # helper method to provide it with newsies specific information when needed i.e. Newsies::List object.
      class ThreadDecorator
        attr_accessor :thread, :list, :user

        def initialize(thread:, list:, user:)
          @thread = thread
          @list = list
          @user = user
        end

        def newsies_thread
          @newsies_thread ||= Newsies::Thread.to_object(thread, list: newsies_list)
        end

        def newsies_list
          @newsies_list ||= ::Newsies::List.to_object(list)
        end

        def managed_by_notifyd?
          thread.respond_to?(:notifyd_primary?) && thread.notifyd_primary?(user)
        end

        def list_key
          newsies_list.key
        end

        def thread_key
          newsies_thread.key
        end
      end

      def self.load(user, thread, list)
        self.for(user).load(ThreadDecorator.new(thread: thread, list: list, user: user))
      end

      def initialize(user)
        @user = user
      end

      def fetch(thread_objects)
        notifyd_threads, newsies_threads = thread_objects.partition(&:managed_by_notifyd?)

        results = {}
        if notifyd_threads.present?
          notifyd_results = notifyd_thread_subscription_results(notifyd_threads)
          return {} if notifyd_results.nil?

          results = results.merge(notifyd_results)
        end

        if newsies_threads.present?
          newsies_results = newsies_thread_subscription_results(newsies_threads)
          return {} if newsies_results.nil?

          results = results.merge(newsies_results)
        end

        results
      end

      private

      # notifyd_thread_subscription_results
      #
      # Calls the notifyd API to get the subscription status for a list of threads in an N+1 fashion.
      # This is done because notifyd does not support batch calls yet.
      #
      # TODO: fix this before we GA notifyd for issues
      #
      # returns Hash<ThreadDecorator, NotificationThreadSubscriptionResult>
      def notifyd_thread_subscription_results(notifyd_threads)
        notifyd_threads.each_with_object({}) do |obj, results|
          list = obj.list
          thread = obj.thread


          response = ::Notifications::Subscriptions.subscription_status(@user, list, thread)

          # Return early with nil and catch in caller if network request fails.
          # This replicates the behavior seen via newsies when we do a single batch call
          # instead of an N+1 call like we do for notifyd.
          return nil unless response.success?
          results[obj] = NotificationThreadSubscriptionResult.new(thread: thread, list: list, valid: response.valid?, ignored: response.ignored?)
        end
      end

      # newsies_thread_subscription_results
      #
      # Calls the newsies API to get the subscription status for a list of threads. This is a batched call.
      #
      # returns Hash<ThreadDecorator, NotificationThreadSubscriptionResult>
      def newsies_thread_subscription_results(newsies_threads)
        threads = newsies_threads.map(&:newsies_thread)
        response = GitHub.newsies.user_thread_subscriptions(@user.id, threads)

        # Return early with nil and catch in caller if network request fails.
        return nil unless response.success?

        subscriptions = response.index_by do |subscription|
          [
            ::Newsies::List.new(subscription.list_type, subscription.list_id).key,
            subscription.thread_key,
          ]
        end

        newsies_threads.each_with_object({}) do |obj, results|
          sub = subscriptions[[obj.list_key, obj.thread_key]]
          results[obj] = NotificationThreadSubscriptionResult.new(thread: obj.thread, list: obj.list, valid: sub.present?, ignored: sub&.ignored? || false)
        end
      end
    end
  end
end
