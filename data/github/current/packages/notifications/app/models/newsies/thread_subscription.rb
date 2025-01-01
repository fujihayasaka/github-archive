# typed: true
# frozen_string_literal: true

module Newsies
  # Responsible for managing the subscribers for a Thread.
  class ThreadSubscription < ApplicationRecord::Domain::Notifications

    self.table_name = :notification_thread_subscriptions
    self.utc_datetime_columns = [:created_at]
    self.record_timestamps = false

    validates :user_id, presence: true
    validates :list_type, presence: true
    validates :list_id, presence: true
    validates :ignored, inclusion: { in: [true, false] }
    validates :thread_key, presence: true

    has_many :subscription_events, class_name: "::Newsies::SubscriptionEvent", as: :subscription, dependent: :delete_all

    DELETE_BATCH_SIZE = 100
    MAX_PAGE_SIZE = 1000

    VALID_THREAD_TYPES = %w[Issue PullRequest Discussion]

    scope :excluding_ignored, ->() {
      where(ignored: false)
    }

    scope :only_ignored, ->() {
      where(ignored: true)
    }

    scope :for_list, ->(list) {
      raise ArgumentError, "list cannot be nil" unless list
      where(list_type: list.type, list_id: list.id)
    }

    # Subscriptions for multiple lists, may be of different list_types
    scope :for_lists, ->(lists) {
      raise ArgumentError, "lists cannot be nil" unless lists
      where(where_condition_for_lists(lists))
    }

    scope :for_thread, ->(thread) {
      raise ArgumentError, "thread cannot be nil" unless thread

      where(
        list_type: thread.list_type,
        list_id: thread.list_id,
        thread_key: thread.key,
      )
    }

    scope :for_threads, ->(threads) {
      raise ArgumentError, "threads cannot be nil" unless threads
      where(where_condition_for_threads(threads))
    }

    scope :for_user, ->(user_id) {
      raise ArgumentError, "user_id cannot be nil" unless user_id
      where(user_id: user_id)
    }

    scope :for_users, ->(user_ids) {
      raise ArgumentError, "user_ids cannot be nil" unless user_ids
      where(user_id: user_ids)
    }

    scope :for_reason, ->(reason) {
      where(reason: reason)
    }
    # Force MySQL to use the correct index when querying this table
    # for more information see: https://github.com/github/github/issues/109527
    #
    # This must be called after all other scopes/where/order calls on a given relation.
    # If certain combinations of FORCE_INDEX_COLUMNS are used in the query then we will
    # force an index. If additional keys not listed in FORCE_INDEX_COLUMNS are also used,
    # we will let mysql decide.
    FORCE_INDEX_COLUMNS = %w[id user_id list_type list_id ignored reason]
    scope :force_index, ->() {
      # we will check the whole query after "WHERE" to ensure we consider ORDER as well
      # as WHERE predicates for used columns
      conditions_part = scoped.to_sql.split(" WHERE ").second

      # if we are querying by any keys not listed, don't try and optimise
      columns_to_ignore = ThreadSubscription.columns.map(&:name) - FORCE_INDEX_COLUMNS
      return all if columns_to_ignore.any? { |column| conditions_part.include?(column) }

      list_id   = conditions_part.include?("list_id")
      list_type = conditions_part.include?("list_type")
      user_id   = conditions_part.include?("user_id")
      reason    = conditions_part.include?("reason")
      ignored   = conditions_part.include?("ignored")

      index = if list_id && user_id && reason && list_type && ignored
        "index_on_list_id_user_id_reason_list_type_ignored"
      elsif list_id && user_id && list_type && ignored
        "index_on_list_id_user_id_list_type_ignored"
      elsif user_id && reason && list_type && ignored
        "index_on_user_id_reason_list_type_ignored"
      elsif user_id && list_type && ignored
        "index_on_user_id_list_type_ignored"
      end

      return all unless index

      from("`#{ThreadSubscription.table_name}` FORCE INDEX (`#{index}`)")
    }

    # Returns a scope for a single page of subscriptions.
    #
    # If the `reveal_next_page` or `reveal_previous_page` arguments are used, the resulting scope
    # may contain up to two items more than `limit`. This is useful for determining whether or not
    # more pages exist in either direction, but it is the responsibility of the client to correctly
    # filter out the extra items.
    #
    # cursor               - Integer ID marking (exclusive) start of page
    # direction            - Symbol (:desc | :asc) indicating direction in which to paginate results
    # limit                - Integer page size
    # reveal_next_page     - Boolean indicating whether or not to return an extra record after the
    #                        end of the requested page.
    # reveal_previous_page - Boolean indicating whether or not to return an extra record before the
    #                        start of the requested page.
    #
    # Returns ActiveRecord::Relation for a single page of subscriptions.
    scope :cursor_paginate, ->(cursor:, direction: :desc, limit: 50, reveal_next_page: false, reveal_previous_page: false) {

      limit += 1 if reveal_next_page
      limit += 1 if reveal_previous_page && cursor

      scope = order(id: direction)

      if cursor && direction == :desc && reveal_previous_page
        scope = scope.where("id <= ?", cursor)
      elsif cursor && direction == :desc
        scope = scope.where("id < ?", cursor)
      elsif cursor && reveal_previous_page
        scope = scope.where("id >= ?", cursor)
      elsif cursor
        scope = scope.where("id > ?", cursor)
      end

      scope.limit(limit)
    }

    # Private: build a WHERE condition for multiple lists, with possibly different list_types
    # With multiple lists, we want to check `list_id IN (ids)`, but we must separate that
    # by list_type to ensure we get the right results.
    #
    # Do not use directly, use via `for_lists` scope.
    #
    # lists - An array of Newsies::List instances
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
    # Returns ["(list_type = ? AND list_id = ? AND thread_key IN (?)) OR ...", value_bindings]
    def self.where_condition_for_threads(threads)
      query_parts = []
      bindings = []
      threads.group_by(&:list).each do |(list, threads_in_list)|
        query_parts.push("(list_type = ? AND list_id = ? AND thread_key IN (?))")
        bindings.push(list.type, list.id, threads_in_list.map(&:key).uniq)
      end
      [query_parts.join(" OR "), *bindings]
    end

    # Public: Subscribes a User to a thread, removing any ignore status.
    #
    # user_id        - An Integer user id.
    # newsies_thread - A Newsies::Thread instance with a Newsies::List populated.
    # options        - Optional ThreadSubscribeOptions object or Hash. Also
    #                  takes just a String reason for legacy compatibility.
    #                  :reason - String reason for the subscription.
    #                  :force  - Whether the reason should clobber any existing
    #                            reason.
    # events         - Array of String event names
    #
    # Returns nothing.
    sig do
      params(user_id: Integer, newsies_thread: Newsies::Thread, options: T.untyped, events: T::Array[String]).void
    end
    def self.subscribe(user_id, newsies_thread, options = nil, events = [])
      struct = ThreadSubscribeOptions.from(options)

      unless struct.reason
        raise ArgumentError.new("Cannot subscribe user #{user_id} to #{newsies_thread.key} without a reason")
      end

      statement = <<-SQL
        INSERT INTO notification_thread_subscriptions
          (user_id, list_type, list_id, thread_key, reason, ignored, created_at)
        VALUES
          (:user_id, :list_type, :list_id, :thread_key, :reason, 0, :created_at)
        ON DUPLICATE KEY UPDATE
          `id` = LAST_INSERT_ID(`id`),
          ignored = 0
      SQL
      if struct.force
        statement += ", reason = :reason"
      else
        statement += ", reason = IFNULL(reason, VALUES(reason))"
      end

      ApplicationRecord::Domain::Notifications.transaction do
        last_insert_id = self.connection.insert(Arel.sql(statement,
          user_id: user_id,
          list_type: newsies_thread.list_type,
          list_id: newsies_thread.list_id,
          thread_key: newsies_thread.key,
          reason: struct.reason,
          created_at: Time.now.to_formatted_s(:db_utc)
        ))

        subscription = ThreadSubscription.find(last_insert_id)
        subscription.subscription_events = events.map do |event_name|
          Newsies::SubscriptionEvent.new(event_name: event_name)
        end
      end

      nil
    end

    # Public: Subscribes an array of user ids to a thread (ie: a specific Issue), removing any ignore status.
    #
    # user_ids    - An array of Integer user ids.
    # newsies_thread - A Newsies::Thread instance with a Newsies::List populated.
    # options     - Optional ThreadSubscribeOptions object or Hash.  Also takes
    #               just a String reason for legacy compatibility.
    #               :reason - String reason for the subscription.
    #               :force  - Whether the reason should clobber any existing
    #                         reason.
    #
    # Returns nothing.
    sig { params(user_ids: T::Array[Integer], newsies_thread: Newsies::Thread, options: T.untyped).void }
    def self.subscribe_all(user_ids, newsies_thread, options = nil)
      struct = ThreadSubscribeOptions.from(options)
      unless reason = struct.reason
        raise ArgumentError.new("Cannot subscribe users #{user_ids} to #{newsies_thread.key} without a reason")
      end

      now = Time.now
      user_data = user_ids.map do |user_id|
        {
          user_id: user_id,
          list_type: newsies_thread.list_type,
          list_id: newsies_thread.list_id,
          thread_key: newsies_thread.key,
          reason: reason,
          ignored: false,
          created_at: now
        }
      end

      on_duplicate_sql = "ignored = 0"
      if reason
        if struct.force
          on_duplicate_sql += ", reason = VALUES(reason)"
        else
          on_duplicate_sql += ", reason = IFNULL(reason, VALUES(reason))"
        end
      end

      upsert_all(user_data, on_duplicate: Arel.sql(on_duplicate_sql))

      nil
    end

    # Public: returns an array of user_ids who are subscribed to any thread for the
    # given list.
    #
    # Includes subscriptions which are marked as "ignore", for completeness.
    #
    # newsies_list - A Newsies::List instance.
    #
    # Returns an Array of Integer user ids.
    sig { params(newsies_list: Newsies::List).returns(T::Array[Integer]) }
    def self.subscribed_user_ids(newsies_list)
      for_list(newsies_list).order(:user_id).distinct.pluck(:user_id)
    end

    # Public: Checks the subscription status for the user.
    #
    # user_id - An Integer user id.
    # thread  - A Newsies::Thread instance with a Newsies::List populated.
    #
    # Returns a Subscription object for the Thread.
    sig { params(user_id: Integer, thread: Newsies::Thread).returns(Subscription) }
    def self.status(user_id, thread)
      thread_subscription = for_user(user_id)
                            .for_thread(thread)
                            .includes(:subscription_events)
                            .first

      return Subscription.not_subscribed(thread.list, thread) unless thread_subscription

      thread_subscription.to_subscription
    end

    # Public: Checks the subscription status to a given thread for an array of users.
    #
    # user_ids  - An array of Integer user ids.
    # thread    - A Newsies::Thread instance with a Newsies::List populated.
    #
    # Returns an Array of Subscriptions.
    sig { params(user_ids: T::Array[Integer], thread: Newsies::Thread).returns(T::Array[Subscription]) }
    def self.status_all(user_ids, thread)
      thread_subscriptions_by_user_id = for_users(user_ids)
                                          .for_thread(thread)
                                          .includes(:subscription_events)
                                          .index_by(&:user_id)

      user_ids.map do |user_id|
        thread_subscription = thread_subscriptions_by_user_id[user_id]

        next Subscription.not_subscribed(thread.list, thread) unless thread_subscription

        thread_subscription.to_subscription
      end
    end

    # Public: Finds all subscribed threads for User across a number of Lists
    #
    # user_id       - An Integer user id.
    # newsies_lists - An Array of Newsies::List instances.
    # thread_type   - String type of thread.
    #
    # Yields a found Subscription if a block is given.
    # Returns an Array of Subscription objects matching threads.
    sig do
      params(
        user_id: Integer,
        newsies_lists: T::Array[Newsies::List],
        thread_type: String
      ).returns(T::Array[Subscription])
    end
    def self.subscribed_threads(user_id, newsies_lists, thread_type)
      return [] if newsies_lists.empty?

      scope = for_user(user_id).for_lists(newsies_lists).excluding_ignored
      scope = scope.where("thread_key LIKE ?", "#{thread_type};%")

      scope.map do |thread_subscription|
        subscription = thread_subscription.to_subscription

        block_given? ? yield(subscription) : subscription
      end
    end

    # Public: Unsubscribes a User from a thread.
    #
    # user_id        - An Integer user id.
    # newsies_thread - A Newsies::Thread instance with a Newsies::List populated.
    #
    # Returns nothing.
    sig { params(user_id: Integer, newsies_thread: Newsies::Thread).void }
    def self.unsubscribe_thread(user_id, newsies_thread)
      for_user(user_id).for_thread(newsies_thread).destroy_all

      nil
    end

    # Public: Sets the User to ignore a specific Thread.
    #
    # user_id     - An Integer user id.
    # newsies_thread - A Newsies::Thread instance with a Newsies::List populated.
    #
    # Returns nothing.
    sig { params(user_id: Integer, newsies_thread: Newsies::Thread).void }
    def self.ignore(user_id, newsies_thread)
      statement = <<-SQL
        INSERT INTO notification_thread_subscriptions
          (user_id, list_type, list_id, thread_key, reason, ignored, created_at)
        VALUES (:user_id, :list_type, :list_id, :thread_key, NULL, 1, :created_at)
        ON DUPLICATE KEY UPDATE
          `id` = LAST_INSERT_ID(`id`),
          ignored = 1,
          reason = NULL
      SQL

      ApplicationRecord::Domain::Notifications.transaction do
        sql = Arel.sql(statement,
          user_id: user_id,
          list_type: newsies_thread.list_type,
          list_id: newsies_thread.list_id,
          thread_key: newsies_thread.key,
          reason: nil,
          ignored: true,
          created_at: Time.now.to_formatted_s(:db_utc)
        )

        last_insert_id = self.connection.insert(sql)
        ThreadSubscription.find(last_insert_id).subscription_events.delete_all
      end

      nil
    end

    # Public: Checks to see which threads are ignored.
    #
    # user_id         - Integer User ID.
    # newsies_threads - An Array of Newsies::Thread instances with
    #                   Newsies::List populated.
    #
    # Returns an Array of Subscriptions.
    sig do
      params(
        user_id: T.any(User, Integer),
        newsies_threads: T::Array[Newsies::Thread]
      ).returns(T::Array[Subscription])
    end
    def self.ignored(user_id, newsies_threads)
      return [] if newsies_threads.blank?

      for_user(user_id)
        .only_ignored
        .for_threads(newsies_threads)
        .includes(:subscription_events)
        .map(&:to_subscription)
    end

    # Public: Allows iterating thread subscriptions in batches.
    #
    # newsies_thread - A Newsies::Thread instance with a Newsies::List populated.
    #
    # Yields Arrays of Newsies::Subscriber objects.
    # Returns nothing.
    sig do
      params(
        newsies_thread: Newsies::Thread,
        block: T.nilable(T.proc.params(subscribers: T::Array[Newsies::Subscriber]).void)
      ).void
    end
    def self.each(newsies_thread, &block)
      raise ArgumentError, "block is required" unless block_given?

      subscribers = T.let(nil, T.nilable(T::Array[Subscriber]))
      max_queried_user_id = T.let(0, Integer)

      while !subscribers || subscribers.size >= MAX_PAGE_SIZE
        scope = for_thread(newsies_thread)
          .where("user_id > ?", max_queried_user_id)
          .includes(:subscription_events)
          .order(user_id: :asc)
          .limit(MAX_PAGE_SIZE)

        subscribers = scope.map do |thread_subscription|
          reason = thread_subscription.reason || default_reason
          Subscriber.new(thread_subscription.user_id, true,
            thread_subscription.ignored, reason, thread_subscription.created_at, thread_subscription.subscription_events.map(&:event_name))
        end

        max_queried_user_id = subscribers.last.try(:user_id)

        block.call(subscribers) unless subscribers.empty?
      end

      nil
    end

    # Public: The default reason for for a subscriber/subscription.
    sig { returns String }
    def self.default_reason
      "thread"
    end

    # Public: Converts the thread subscriptions into a Subscription object.
    sig { returns Subscription }
    def to_subscription
      list = Newsies::List.new(list_type, list_id)
      thread = Newsies::Thread.from_key(thread_key, list: list)
      Subscription.new(list, thread, true, ignored, reason.to_s, created_at, subscription_events.map(&:event_name))
    end

    sig { returns Promise[T.untyped] }
    def async_list
      Platform::Loaders::ActiveRecord.load(list_type.constantize, list_id)
    end

    # Asynchronously load the thread object that the user has subscribed to with this subscription.
    #
    # Returns Promise<Issue|PullRequest|Discussion>.
    sig { returns T.any(Promise[T.any(Issue, PullRequest, Discussion)], Promise[NilClass]) }
    def async_thread
      thread = Newsies::Thread.from_key(thread_key, list: Newsies::List.new(list_type, list_id))

      if thread.type == "Grit::Commit"
        # async_thread passes through async_readable_by which filters non-readable threads
        return Platform::Loaders::ActiveRecord.load(thread.list_type.constantize, thread.list_id, security_violation_behaviour: :allow).then do |repo|
          fetch_commit(repo, thread.id)
        end
      end

      # These are the only thread types we care to support at the moment.
      return Promise.resolve(nil) unless VALID_THREAD_TYPES.include?(thread.type)

      promise = Platform::Loaders::ActiveRecord.load(thread.type.constantize, thread.id.to_i)

      if thread.type == "Issue"
        # Dodge https://github.com/github/github/issues/106506
        promise = promise.then do |issue|
          if issue
            issue.async_pull_request.then do |pull_request|
              next pull_request if pull_request.present?
              issue
            end
          end
        end
      end

      promise
    end

    def fetch_commit(repo, thread_id)
      return Promise.resolve(nil) if repo.nil?
      repo.commits.find(thread_id)
    rescue GitRPC::ObjectMissing
      Promise.resolve(nil)
    end

    def async_readable_by?(viewer, unauthorized_account_ids:)
      async_thread.then do |thread|
        next false unless thread

        thread.async_repository.then do |repo|
          next false unless repo

          (repo.try(:async_owner) || repo.try(:async_organization)).then do |owner|
            next false if owner && unauthorized_account_ids.include?(owner.id)

            thread.async_hide_from_user?(viewer).then do |thread_is_spammy|
              next false if thread_is_spammy

              thread.async_readable_by?(viewer).then do |is_readable|
                next false unless is_readable

                repo.async_visible_and_readable_by?(viewer)
              end
            end
          end
        end
      end
    end
  end
end
