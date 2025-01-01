# typed: true
# frozen_string_literal: true

# Query class for notification_deliveries.  READ ONLY
# Notification deliveries are a log of each individual
# web and email notification that has been delivered.
module Newsies
  class NotificationDelivery < ApplicationRecord::Domain::NotificationsDeliveries
    self.utc_datetime_columns = [:delivered_at]

    # Public: Performs a batch save of the delivered notifications.
    #
    # list_id    - The Integer List ID.
    # thread_key - The String Thread key.
    # comment_id - The Integer Comment ID.
    # hash       - A Hash of Integer User ID keys and Hash handler details.
    #
    # Returns nothing.
    def self.batch_create_from_handler_data(list_id, thread_key, comment_key, hash)

      return if hash.empty?

      now = Time.now.utc
      values = []
      list_id = list_id.to_i

      hash.each do |user_id, handlers_and_reasons|
        handlers = {}

        handlers_and_reasons.reverse_each do |(h, r)|
          handlers[h] = r if h
        end

        user_id = user_id.to_i

        handlers.each do |handler, reason|
          next if skip_writing_record?(user_id, handler, thread_key, reason)
          values << {
            list_id: list_id,
            thread_key: thread_key,
            comment_key: comment_key,
            user_id: user_id,
            handler: handler,
            reason: reason || "",
            delivered_at: now
          }
        end
      end

      on_duplicate_sql = Arel.sql("reason = VALUES(reason)")
      values.in_groups_of(100, false) do |rows|
        upsert_all(rows, on_duplicate: on_duplicate_sql)
      end
    end

    # Don't write records for repository watchers for the web handler
    # as no longer required to avoid duplication
    def self.skip_writing_record?(user_id, handler, thread_key, reason)
      handler.to_s == "web" &&
        thread_key.starts_with?("Issue;") &&
        reason.to_s == "list"
    end

    # Public: Loads previous deliveries for the given user IDs in the given
    # Thread.
    #
    # list_id    - The Integer List ID.
    # thread_key - The String Thread key.
    # comment_id - The Integer Comment ID.
    # user_ids   - Array of Integer User IDs.
    #
    # Returns a Hash of Integer User ID keys and Hash handler details.
    def self.handler_data(list_id, thread_key, comment_key, user_ids)
      deliveries = {}
      return deliveries if user_ids.empty?

      scope = NotificationDelivery.where(list_id: list_id, thread_key: thread_key,
        comment_key: comment_key, user_id: user_ids)

      scope.pluck(:user_id, :handler, :reason).each do |user_id, handler, reason|
        (deliveries[user_id] ||= {})[handler] = reason
      end

      deliveries
    end

    # Public: Shows notification deliveries for a specific user.
    #
    # user    - A User.
    # repo    - A Repository.
    # options - Optional Hash.
    #           :thread  - A String thread key in the form of "class;id"
    #           :comment - A String comment key in the form of "class;id"
    #           :handler - String handler name: "web" or "email"
    #
    # Returns an Array of Newsies::NotificationDelivery objects.
    def self.by_user(user, repo, options = {})
      filter(repo, options, [["user_id = ?"], user.id])
    end

    # Public: Shows notification deliveries for a Repository.
    #
    # repo    - A Repository.
    # options - Optional Hash.
    #           :thread  - A String thread key in the form of "class;id"
    #           :comment - A String comment key in the form of "class;id"
    #           :handler - String handler name: "web" or "email"
    #
    # Returns an Array of Newsies::NotificationDelivery objects.
    def self.by_repository(repo, options = {})
      filter(repo, options)
    end

    # Handles the actual building and executing of the query to select tracked
    # notification deliveries.
    #
    # repo    - An object that references a Repository, such as a Commit,
    #           Issue, IssueComment, PullRequestReviewComment, CommitComment, or
    #           a Repository.
    # options - Optional Hash.
    #           :thread  - A String thread key in the form of "class;id"
    #           :comment - A String comment key in the form of "class;id"
    #           :handler - String handler name: "web" or "email"
    # cond    - Array of ActiveRecord conditions.
    #
    # Returns an Array of Newsies::NotificationDelivery objects.
    def self.filter(repo, options = {}, cond = [[]])
      repo_id = repo.id if repo

      if repo_id
        cond.first << "list_id = ?"
        cond << repo_id
      end

      if key = options[:thread]
        cond.first << "thread_key = ?"
        cond << key
      end

      if key = options[:comment]
        cond.first << "comment_key = ?"
        cond << key
      end

      if handler = options[:handler]
        cond.first << "handler = ?"
        cond << handler
      end

      if before = options[:before]
        cond.first << "delivered_at <= ?"
        cond << before
      end

      cond.unshift cond.shift.join(" and ")
      # raise options.inspect + "\n" + cond.inspect
      preload conditions: cond, limit: 100, order: "delivered_at desc"
    end

    attr_accessor :user, :repository

    def readonly?
      true
    end

    def thread_class
      newsies_thread.type
    end

    def thread_id
      newsies_thread.id
    end

    def newsies_thread
      @newsies_thread ||= Newsies::Thread.from_key(thread_key)
    end

    def self.preload(*args)
      query = *args

      Newsies::Responses::Array.new do
        tracked = with_utc do
          where(query.first[:conditions]).
          limit(query.first[:limit]).
          order(Arel.sql(query.first[:order])).to_a
        end
        repo_ids = tracked.map { |t| t.list_id }
        repo_ids.uniq!
        user_ids = tracked.map { |t| t.user_id }
        user_ids.uniq!
        repos = Repository.includes(:owner).where(id: repo_ids).index_by { |r| r.id }
        users = User.where(id: user_ids).index_by { |u| u.id }
        tracked.each do |t|
          t.repository = repos[t.list_id.to_i]
          t.user = users[t.user_id.to_i]
        end
      end
    end

    def self.with_utc
      old_tz = ActiveRecord.default_timezone
      ActiveRecord.default_timezone = :utc
      yield
    ensure
      ActiveRecord.default_timezone = old_tz
    end
  end
end
