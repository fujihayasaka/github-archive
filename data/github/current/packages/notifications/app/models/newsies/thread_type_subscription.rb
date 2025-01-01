# typed: false
# frozen_string_literal: true

module Newsies
  # Responsible for managing the subscribers to a type of thread within a list
  # e.g. Release (thread type) threads for a Repository (list).
  class ThreadTypeSubscription < ApplicationRecord::Domain::Notifications
    self.table_name = :notification_thread_type_subscriptions
    self.utc_datetime_columns = [:created_at]
    self.record_timestamps = false

    DEFAULT_REASON = "thread_type"
    DEFAULT_PAGE_SIZE = 100
    DEFAULT_BATCH_SIZE = 1000

    belongs_to :list, polymorphic: true, foreign_key: :list_id, foreign_type: :list_type, optional: true

    scope :for_list, ->(newsies_list) {
      where(list_type: newsies_list.type, list_id: newsies_list.id)
    }

    scope :for_lists, ->(lists) {
      raise ArgumentError, "lists cannot be blank" unless lists.present?
      where(where_condition_for_lists(lists))
    }

    scope :excluding_lists, ->(lists) {
      raise ArgumentError, "lists cannot be blank" unless lists.present?
      where.not(where_condition_for_lists(lists))
    }

    scope :for_thread_type, ->(thread_type) {
      where(thread_type: thread_type)
    }

    scope :for_threads, ->(threads) {
      raise ArgumentError, "threads cannot be blank" unless threads.present?
      where(where_condition_for_threads(threads))
    }

    scope :for_user, ->(user_id) {
      where(user_id: user_id)
    }

    scope :for_users, ->(user_ids) {
      where(user_id: user_ids)
    }

    # Private: build a WHERE condition for multiple lists, with possibly different list_types
    # With multiple lists, we want to check `list_id IN (ids)`, but we must separate that
    # by list_type to ensure we get the right results
    #
    # Do not use directly, use via `for_lists`
    #
    # lists - An array of Newsies::List intances
    #
    # Returns ["(list_type = ? AND list_id IN (?)) OR ...", value_bindings]
    def self.where_condition_for_lists(lists)
      query_parts = []
      bindings = []
      lists.group_by(&:type).each do |(list_type, lists_of_type)|
        query_parts.push("(list_type = ? AND list_id IN (?))")
        bindings.push(list_type, lists_of_type.map(&:id))
      end
      [query_parts.join(" OR "), *bindings]
    end

    # Private: build a WHERE condition for multiple threads.
    #
    # Do not use directly, use via `for_threads` scope.
    #
    # threads - An array of Newsies::Thread instances
    #
    # Returns ["(list_type = ? AND list_id = ? AND thread_type IN (?)) OR ...", value_bindings]
    def self.where_condition_for_threads(threads)
      query_parts = []
      bindings = []
      threads.group_by(&:list).each do |(list, threads_in_list)|
        query_parts.push("(list_type = ? AND list_id = ? AND thread_type IN (?))")
        bindings.push(list.type, list.id, threads_in_list.map(&:subscription_type).uniq)
      end
      [query_parts.join(" OR "), *bindings]
    end

    # Public: Subscribes a user to multiple thread types
    #
    # This method will remove all existing thread type subscriptions for a given user + list
    # and replace with the new thread types provided.
    #
    # Returns Array of primary key ids for the successfully inserted records
    def self.subscribe_to_thread_types(user_id, newsies_list, thread_types)
      values_to_insert = thread_types.map do |thread_type|
        {
          user_id: user_id,
          list_type: newsies_list.type,
          list_id: newsies_list.id,
          thread_type: thread_type,
          created_at: Time.now.utc,
        }
      end

      transaction do
        ThreadTypeSubscription.for_user(user_id).for_list(newsies_list).destroy_all
        create(values_to_insert)
      end
    end

    # Public: Get all the thread types a user is subscribed to for a given list.
    #
    # user_id      - An Integer user id
    # newsies_list - A Newsies::List instance
    def self.subscribed_thread_types(user_id, newsies_list)
      for_user(user_id).for_list(newsies_list).pluck(:thread_type)
    end

    # Public: Unsubscribes a User from all thread types for the given list.
    #
    # user_id      - An Integer user id.
    # newsies_list - A Newsies::List instance
    #
    # Returns nothing.
    def self.unsubscribe_from_all_thread_types_for_list(user_id, newsies_list)
      unsubscribe_from_all_thread_types_for_multiple_lists(user_id, [newsies_list])
    end

    # Public: Unsubscribes a User from all thread types for each given list.
    #
    # user_id       - An Integer user id.
    # newsies_lists - An array of Newsies::List instance
    #
    # Returns nothing.
    def self.unsubscribe_from_all_thread_types_for_multiple_lists(user_id, newsies_lists)
      for_user(user_id).for_lists(newsies_lists).delete_all
    end

    def self.subscriptions(user_id, page: nil, per_page: nil, excluding: nil, sort: :desc, list_type: "Repository", thread_type: nil)
      list_ids = subscriptions_list_ids(user_id, page: page, per_page: per_page, excluding: excluding, sort: sort, list_type: list_type, thread_type: thread_type)
      # Then we can load all the ThreadTypeSubscriptions and group them by list
      list_ids_to_subscriptions = for_user(user_id)
                                    .where(list_type: list_type)
                                    .where(list_id: list_ids)
                                    .includes(:list)
                                    .group_by(&:list_id)

      # Iterate the original list_ids list to ensure the ordering is respected in the result
      list_ids.map do |list_id|
        thread_type_subscriptions = list_ids_to_subscriptions[list_id]

        newsies_list = Newsies::List.new(list_type, list_id)
        list_object = thread_type_subscriptions.first.list

        subscription = Subscription.custom_list_subscription(
          list: newsies_list,
          reason: DEFAULT_REASON,
          thread_types: thread_type_subscriptions.map(&:thread_type),
          created_at: thread_type_subscriptions.map(&:created_at).max
        )
        subscription.list_object = list_object
        subscription
      end
    end

    def self.subscriptions_list_ids(user_id, page: nil, per_page: nil, excluding: nil, sort: :desc, list_type: "Repository", thread_type: nil)
      page ||= 1
      per_page ||= DEFAULT_PAGE_SIZE

      # A single list can have multiple ThreadTypeSubscriptions so we first find all the unique repositories
      # for the user with a relevant ThreadTypeSubscription
      list_ids_scope = for_user(user_id)
                        .where(list_type: list_type)
                        .order(id: sort)
                        .offset((page - 1) * per_page)
                        .limit(per_page)

      list_ids_scope = list_ids_scope.for_thread_type(thread_type) if thread_type.present?
      list_ids_scope = list_ids_scope.excluding_lists(excluding) if excluding.present?

      list_ids_scope.distinct.pluck(:list_id)
    end

    def self.count_subscriptions(user_id, list_type: "Repository", thread_type: nil)
      scope = for_user(user_id)
                .where(list_type: list_type)

      scope = scope.for_thread_type(thread_type) if thread_type.present?

      scope.distinct.count(:list_id)
    end

    def to_subscriber
      Subscriber.new(user_id, true, false, DEFAULT_REASON, created_at)
    end
  end
end
