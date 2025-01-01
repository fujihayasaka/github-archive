# typed: true
# frozen_string_literal: true

module Newsies
  class NotificationEntry < ApplicationRecord::Domain::NotificationsEntries
    self.utc_datetime_columns = [:updated_at, :last_read_at]
    self.record_timestamps = false

    belongs_to :notification_summary, class_name: "NotificationSummary", foreign_key: "summary_id" # rubocop:todo Rails/InverseOf

    attribute :unread, :integer
    enum :unread, {
      inbox_read: 0,
      inbox_unread: 1,
      archived: 2,
    }
    alias_attribute :status, :unread

    def unread?
      inbox_unread?
    end

    def read?
      inbox_read?
    end

    def status?
      unread.present?
    end

    def self.statuses
      self.unreads
    end

    # Some users have notifications for more lists than we can count
    # in a single request. See https://github.com/github/github/issues/116497
    COUNT_BY_LIST_LIMIT = 250
    DELETE_BATCH_SIZE = 100

    PARTICIPATING_REASONS = %w[
      comment
      mention
      author
      team_mention
      assign
      manual
      state_change
      invitation
      review_requested
      security_advisory_credit
    ].freeze

    # Map the states used by V2 to the internal Newsies states
    V2_STATE_TO_INTERNAL_STATE = {
      read: :inbox_read,
      unread: :inbox_unread,
      archived: :archived,
    }.freeze

    FOCUS_REASONS = %w[
      assign
      mention
      review_requested
      member_feature_requested
    ].freeze

    scope :for_user, ->(user_id) {
      raise ArgumentError, "user_id cannot be nil" unless user_id
      where(user_id: user_id)
    }

    scope :for_users, ->(user_ids) {
      raise ArgumentError, "user_id cannot be nil" unless user_ids
      where(user_id: user_ids)
    }

    scope :for_owners, ->(owner_ids) {
      raise ArgumentError, "owner_ids cannot be nil" unless owner_ids
      where(owner_id: owner_ids)
    }

    scope :exclude_owners, ->(owner_ids) {
      raise ArgumentError, "owner_ids cannot be nil" unless owner_ids
      where.not(owner_id: owner_ids)
    }

    scope :for_authors, ->(author_ids) {
      raise ArgumentError, "author_ids cannot be nil" unless author_ids
      where(author_id: author_ids)
    }

    scope :for_summary, ->(summary_id) {
      raise ArgumentError, "summary_id cannot be nil" unless summary_id
      where(summary_id: summary_id)
    }

    scope :for_summaries, ->(summary_ids) {
      raise ArgumentError, "summary_ids cannot be nil" unless summary_ids
      where(summary_id: summary_ids)
    }

    scope :for_list, ->(list) {
      raise ArgumentError, "list cannot be nil" unless list
      where(
        list_type: list.type,
        list_id: list.id,
      )
    }

    scope :for_thread, ->(thread) {
      raise ArgumentError, "thread cannot be nil" unless thread
      where(
        list_type: thread.list_type,
        list_id: thread.list_id,
        thread_key: thread.list_id_key,
      )
    }

    scope :for_threads, ->(threads) {
      raise ArgumentError, "threads cannot be nil" unless threads
      where(where_condition_for_threads(threads))
    }

    scope :participating, ->() {
      where(reason: PARTICIPATING_REASONS)
    }

    scope :unread, ->() {
      where(status: [:inbox_unread])
    }

    scope :read, ->() {
      where(status: [:inbox_read, :archived])
    }

    # Entries for multiple lists, may be of different list_types
    scope :for_lists, ->(lists) {
      raise ArgumentError, "lists cannot be nil" unless lists
      next NotificationEntry.default_scoped.none if lists.empty?

      where(where_condition_for_lists(lists))
    }

    # Subscriptions excluding multiple lists, may be of different list_types
    scope :excluding_lists, ->(lists) {
      raise ArgumentError, "lists cannot be nil" unless lists
      where.not(where_condition_for_lists(lists))
    }

    # We must use these, and cast times to strings, to ensure UTC times are handled
    # correctly. See ApplicationRecord::UTCTimeType for more.
    scope :updated_before, ->(time) {
      where("#{table_name}.updated_at < ?", time.utc.strftime("%Y-%m-%d %H:%M:%S"))
    }

    # We must use these, and cast times to strings, to ensure UTC times are handled
    # correctly. See ApplicationRecord::UTCTimeType for more.
    scope :updated_since, ->(time) {
      where("#{table_name}.updated_at > ?", time.utc.strftime("%Y-%m-%d %H:%M:%S"))
    }

    # Entries which are not assign, mention, or review_requested reason or authored by the user
    #
    # This is a temporary solution to allow the Hyperlist client to run OR queries, i.e.:
    # `reason:assign OR reason:mention OR reason:review_requested OR author_id:123`
    scope :focus, ->(author_id) {
      where(reason: FOCUS_REASONS).or(where(author_id: author_id))
    }

    # Entries which are not assign, mention, or review_requested reason and not authored by the user
    #
    # As above, this is a temporary solution to allow the Hyperlist client to run NOT queries, i.e.:
    # `NOT (reason:assign OR reason:mention OR reason:review_requested) AND NOT author_id:123`
    scope :not_focus_team_mentioned, ->(author_id) {
      where.not(reason: FOCUS_REASONS + %w[team_mention]).where.not(author_id: author_id)
    }

    # Private: build a WHERE condition for multiple lists, with possibly different list_types
    # With multiple lists, we want to check `list_id IN (ids)`, but we must separate that
    # by list_type to ensure we get the right results
    #
    # Do not use directly, use via `for_lists` and `excluding_lists` scopes
    #
    # lists - An array of Newsies::List intances
    #
    # Returns ["(list_type = ? AND list_id IN (?)) OR ...", value_bindings]
    def self.where_condition_for_lists(lists)
      query_parts = []
      bindings = []
      lists.group_by { |list| Newsies::List.to_type(list) }.each do |(list_type, lists_of_type)|
        query_parts.push("(#{table_name}.list_type = ? AND #{table_name}.list_id IN (?))")
        bindings.push(list_type, lists_of_type.map(&:id))
      end
      [query_parts.join(" OR "), *bindings]
    end

    # Private: build a WHERE condition for multiple threads, with possibly different lists
    # With multiple threaads, we want to check `thread_key IN (ids)`, but we must separate that
    # by list_type and list_id to ensure we get the right results
    #
    # Do not use directly, use via `for_threads` scope
    #
    # lists - An array of Newsies::List intances
    #
    # Returns ["(list_type = ? AND list_id = ? AND thread_key IN (?)) OR ...", value_bindings]
    def self.where_condition_for_threads(threads)
      query_parts = []
      bindings = []
      threads.group_by(&:list).map do |list, threads|
        query_parts.push("(#{table_name}.list_type = ? AND #{table_name}.list_id = ? AND thread_key IN (?))")
        bindings.push(list.type, list.id, threads.map(&:list_id_key))
      end
      [query_parts.join(" OR "), *bindings]
    end

    # Public: Inserts the Summary into the User's sets.
    #
    # user_id_or_settings_id - The user_id who the notification is for.
    # summary                - An instance of NotificationSummary.
    # reason                 - (Optional) Symbol reason user is receiving this notification
    # event_time             - The Time that the triggering event happened
    #                          used to decide if this is a "new" notification for this user
    #                          notifications will not be marked as unread/updated if their
    #                          existing updated_at column is newer than this time
    #
    # Returns: Symbol describing what happened
    #   :delivered      - a new notification was inserted, or an existing one updated
    #   :updated_reason - an up-to-date notification already existed, but the reason needed to be updated
    #   :skipped        - an up-to-date notification already existed, so no change was required
    def self.insert(user_id_or_settings_id, summary, event_time: nil, reason: nil)
      options ||= {}

      summary_hash = summary.to_summary_hash
      summary_id = summary.id
      owner_id = summary.list_owner_id
      author_id = summary.thread_author_id

      list_type, list_id, thread_key = summary_to_list_and_thread_keys(summary_hash)

      args = {
        list_type: list_type,
        list_id: list_id.to_i,
        reason: reason,
        summary_id: summary_id,
        thread_key: thread_key || "",
        event_time: (event_time || Time.now).to_formatted_s(:db_utc),
        updated_at: Time.now.to_formatted_s(:db_utc),
        user_id: user_id_or_settings_id,
        unread: Newsies::NotificationEntry.statuses[:inbox_unread],
        owner_id: owner_id,
        author_id: author_id
      }

      insert_statement = <<-SQL
        INSERT INTO notification_entries
          (user_id, author_id, owner_id, summary_id, list_type, list_id,
            thread_key, unread, reason, updated_at)
        VALUES
          (:user_id, :author_id, :owner_id, :summary_id, :list_type, :list_id,
            :thread_key, :unread, :reason, :updated_at)
      SQL
      connection = self.connection

      # Note: updated_at MUST be last in this list as MySQL immediately applies updates to the record from first to last
      #       so if it's first, the later updates will be skipped
      sql = connection.to_sql(Arel.sql(<<-SQL, **args))
        #{insert_statement}
        ON DUPLICATE KEY UPDATE
          reason =     :reason,
          unread =     IF(updated_at IS NULL || updated_at < :event_time, :unread, unread),
          updated_at = IF(updated_at IS NULL || updated_at < :event_time, :updated_at, updated_at)
      SQL

      connection.execute(sql)
    end

    # Public: Marks the Summary as read for the User.
    #
    # operation   - Symbol of the operation to perform (:read, :unread).
    # user_id     - The user_id to perform the operation against.
    # summary_ids - An Array of NotificationSummary instances.
    #
    # Returns nothing.
    def self.mark_summaries(operation, user_id, summary_ids)
      scope = for_user(user_id).for_summaries(summary_ids)
      mark_scope_as(operation, scope)
    end

    # Public: Marks single NotificationSummary as read for the user_id.
    #
    # operation   - Symbol of the operation to perform (:read, :unread).
    # user_id     - The user_id to perform the operation against.
    # summary_id  - A NotificationSummary id to mark as read.
    #
    # Returns nothing.
    def self.mark_summary(operation, user_id, summary_id)
      mark_summaries operation, user_id, [summary_id]
    end

    # Public: Marks the thread as read for the User.
    #
    # operation - Symbol determining the option being performed.  See
    #             #update_summary_clause.
    # user_id   - The user_id to perform the operation against.
    # thread    - The Newsies::Thread instance including a Newsies::List.
    #
    # Returns nothing.
    def self.mark_thread(operation, user_id, thread)
      scope = for_user(user_id).for_thread(thread)
      mark_scope_as(operation, scope)
    end

    # Public: Marks all notifications as read for a user.
    #
    # time    - Time that the items were viewed last (to ensure that we don't mark newer items).
    # user_id - The user_id to perform the operation against.
    # list    - Optional Newsies::List object to scope the operation against.
    #
    # Returns nothing.
    def self.mark_all(time, user_id, list = nil)
      # set this here before we batch, to ensure everything gets the same last_read_at time
      last_read_at = Time.now.utc

      ids_to_update = ActiveRecord::Base.connected_to(role: :reading) do
        scope = for_user(user_id).updated_before(time).unread
        scope = scope.for_list(list) if list
        scope.pluck(:id)
      end

      ids_to_update.each_slice(100) do |slice|
        where(id: slice).update_all(unread: Newsies::NotificationEntry.statuses[:inbox_read], last_read_at: last_read_at)
      end
    end

    # Public: Marks all notifications in the scope with the given state.
    #
    # scope     - scope to perform bulk update on
    # operation - symbol determining the option being performed
    # mark_at   - UTC timestamp to mark
    #             (only needed for :read, defaults to Time.now.utc)
    #
    # Returns nothing.
    def self.mark_scope_as(operation, scope, mark_at = Time.now.utc)
      case operation
      when :read
        scope.update_all(unread: Newsies::NotificationEntry.statuses[:inbox_read], last_read_at: mark_at)
      when :unread
        scope.update_all(unread: Newsies::NotificationEntry.statuses[:inbox_unread])
      when :archived
        scope.update_all(unread: Newsies::NotificationEntry.statuses[:archived])
      else
        raise ArgumentError, "Unknown operation: #{operation.inspect}"
      end

      nil
    end

    # Public: Gets a page of NotificationEntries that a User was notified of.
    #
    # user_id - The User id to find entries for.
    # options - Optional Hash used to filter the query.
    #           See Newsies::Web::FilterOptions.
    #
    # Returns an Array of NotificationEntry objects.
    def self.for_user_with_options(user_id, options = nil)
      options = Newsies::Web::FilterOptions.from(options)

      # MySQL often gets confused by this query and picks non-performant indexes
      # There are a few queries we _know_ what the best index will be for this query:
      # See https://github.com/github/project-nova/issues/311 for more
      #
      # WHERE user_id = ? ORDER BY updated_at DESC LIMIT ?
      #  - the best index is `index_notification_entries_on_user_id_and_updated_at` (user_id, updated_at)
      #
      # WHERE user_id = ? AND unread = ? ORDER BY updated_at DESC LIMIT ?
      #  - the best index is `user_id_and_unread_and_updated_at ` (user_id, unread, updated_at)
      #
      # WHERE user_id = ? AND unread IN (?) ORDER BY updated_at DESC LIMIT ?
      #  - the best index is `index_notification_entries_on_user_id_and_updated_at ` (user_id, updated_at)
      #
      # any of the above combined with  AND thread_key LIKE '%;?;%'
      #  - use whichever index is best for the other conditions
      #
      # If we filter by any other columns there are other indexes which might perform better, so we cannot safely
      # use force index.

      # list_type / list_id is included in other indexes
      filters_lists = options.list_type || options.list || options.lists || options.excluding.present?
      # reasons included in other indexes
      filters_reasons = options.participating || options.reasons
      # We only apply the forced index in cases where we know we can pick the right index
      apply_forced_index = !filters_lists && !filters_reasons && !options.saved

      scope = if apply_forced_index
        # If it's safe to apply a forced index, we pick which one to use based on whether we query
        # unread for a single value (e.g. `unread = 1`) or we query it for no/multiple values (`unread IN (0,1)`)
        queries_single_unread_value = !options.read && (options.unread || options.statuses&.length == 1)
        if queries_single_unread_value
          # Index on (user_id, unread, updated_at)
          from("notification_entries FORCE INDEX (user_id_and_unread_and_updated_at)")
        else
          # Index on (user_id, updated_at)
          from("notification_entries FORCE INDEX (index_notification_entries_on_user_id_and_updated_at)")
        end
      else
        self
      end

      scope
        .for_user(user_id)
        .scope_from_options(options)
        .order(updated_at: :desc)
        .offset(options.offset)
        .limit(options.per_page)
    end

    # Public: Counts notifications for a user.
    #
    # user_id - The User id to count entries for.
    # options - Optional Hash used to filter the query.
    #           See Newsies::Web::FilterOptions.
    #
    # Returns an Integer count.
    def self.count(user_id, options = nil)
      count_limit = (options || {})[:count_limit]

      scope = for_user(user_id).scope_from_options(options)

      # Counts for very large numbers of rows can be slow.
      # If a count limit is passed, we see if any row exists above
      # OFFSET count_limit, and if it does we just return the count_limit
      if count_limit
        start = Time.now
        above_limit = scope.order(id: :asc).offset(count_limit).exists?
        elapsed_ms = (Time.now - start) * 1_000
        GitHub.dogstats.timing(
          "newsies.notifications_entries_count_limit",
          elapsed_ms,
          tags: ["value:#{above_limit}"])

        return ApproximateCount.new(count_limit, accurate: false) if above_limit
      end

      accurate_count = GitHub.dogstats.time("newsies.notification_entries_count") { scope.count }
      ApproximateCount.new(accurate_count)
    end

    # Public: Checks to see if any notifications exist for the user.
    #
    # user_id - The User id to check if notifications exist for.
    # options - Optional Hash used to filter the query.
    #           See Newsies::Web::FilterOptions.
    #
    # Returns a Boolean.
    def self.exist?(user_id, options = nil)
      for_user(user_id).scope_from_options(options).exists?
    end

    # Public: Counts notifications for a user, with values grouped by list type and list id.
    #
    # user_id - The User id to count notifications for.
    # options - Optional hash to further filter the query.
    #           See Newsies::Web::FilterOptions.
    #
    # Returns an Array of Arrays, representing grouped counts.
    # Each element of the array is of the form:
    #
    # [ list_type, list_id, count, unread_count]
    #
    #   - list_type:    newsies list type string (e.g. "Repository")
    #   - list_id:      database id for the relevant list object
    #   - count:        count of notifications for the list, that match the passed `options` filters
    #   - unread_count: count of _unread_ notifications for the list, that also match the passed `options` filters
    def self.counts_by_list(user_id, options = nil)
      for_user(user_id)
        .scope_from_options(options)
        .group(:list_type, :list_id)
        .limit(COUNT_BY_LIST_LIMIT)
        .pluck(
          :list_type,
          :list_id,
          # Count everything for total count
          Arel.sql("COUNT(*)"),
          # Count unread rows only, casts to INTEGER to match the return type of `COUNT`
          Arel.sql(sanitize_sql(["CAST(SUM(CASE WHEN unread = ? THEN 1 ELSE 0 END) AS UNSIGNED INTEGER)", statuses[:inbox_unread]])),
        )
    end

    # Public: Removes the Summary from the user's notification streams.
    #
    # user_id - The Integer id of the User.
    # summary_id - The Integer id of the NotificationSummary.
    #
    # Returns nothing.
    def self.delete(user_id, summary_id)
      for_user(user_id).for_summary(summary_id).delete_all

      nil
    end

    # Public: Looks up NotificationEntries for a user given a number of
    # threads.
    #
    # user_id - The User id to perform the operation against.
    # threads - An Array of Newsies::Thread instances with list populated.
    #
    # Returns an Array of NotificationEntry objects in the order of the given
    # thread_keys.
    def self.for_user_and_threads(user_id, threads)
      # TODO(abeaumont): Manual timing metric and related logs is a temporary hack
      # to debug https://github.com/github/notifications/issues/2189.
      # Tracing support should be enough in general.
      t0 = Time.now

      result = GitHub.tracer.in_span(
        "for_user_and_threads",
        kind: :internal,
        attributes: {
          "code.namespace" => self.name,
          "gh.notifications.for_user_and_threads.threads.count" => threads.size
        }
      ) do
        track_time("notification_entry.for_user_and_threads.dist.time") do
          threads = Array(threads)
          return [] if threads.empty?

          threads.each do |thread|
            if thread.list.blank?
              raise ArgumentError, "list is required, but was missing for #{thread.inspect}"
            end
          end

          entries_by_thread_key = for_user(user_id).for_threads(threads).index_by(&:thread_key)

          # return notification entries in same order as threads, removing any that didn't exist
          threads.map { |thread| entries_by_thread_key[thread.list_id_key] }.compact
        end
      end

      elapsed_ms = (Time.now - t0)
      GitHub.dogstats.distribution("newsies.notification_entry.for_user_and_threads", elapsed_ms)
      if elapsed_ms > 8000
        GitHub.logger.info("Slow query", {
          "code.namespace" => "Newsies::NotificationEntry",
          "code.function" => "for_user_and_threads",
          "gh.user.id" => user_id,
          "gh.notifications.threads" => threads.map(&:list_id_key).join(",")
        })
      end

      result
    end

    def self.track_time(metric, &blk)
      start_time = GitHub::Dogstats.monotonic_time
      result = yield
      elapsed = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution(metric, elapsed)
      result
    end

    scope :scope_from_options, ->(hash_or_options = nil) do
      options = Newsies::Web::FilterOptions.from(hash_or_options)
      scope = all

      if options.list
        scope = scope.for_list(Newsies::List.to_object(options.list))

        if options.thread_type
          thread_key = "%i;%s;%%" % [options.list.id, options.thread_type]
          scope = scope.where("#{table_name}.thread_key LIKE ?", thread_key)
        end
      end

      # Caution: potentially poor performance
      # Build a scope for filtering by thread types
      # unfortunately because the thread keys are of the form: `${list_id}:#{thread_type}:#{thread_id}`
      # this must be built to a query like: `WHERE (thread_key LIKE '%;Issue;%' OR thread_key LIKE '%;Release;%')`
      # which will not be able to use an index
      #
      # If `options.thread_types` is present but empty, no results will be returned
      if options.thread_types
        thread_type_scope = none
        options.thread_types.each do |thread_type|
          thread_type_like = "%;#{sanitize_sql_like(Newsies::Thread.type_from_class(thread_type.constantize))};%"
          thread_type_scope = thread_type_scope.or(where("#{table_name}.thread_key LIKE ?", thread_type_like))
        end
        # merges the OR conditions into the main scope
        scope = scope.merge(thread_type_scope)
      end

      scope = scope.for_lists(Newsies::List.to_objects(options.lists)) if options.lists
      scope = scope.where(reason: options.reasons) if options.reasons

      scope = scope.unread if options.unread
      scope = scope.read if options.read
      scope = scope.participating if options.participating
      scope = scope.where(status: options.statuses) if options.statuses

      scope = scope.updated_since(options.since_time) if options.since_time
      scope = scope.updated_before(options.before_time) if options.before_time

      scope = scope.where(list_type: options.list_type) if options.list_type
      scope = scope.excluding_lists(options.excluding) if options.excluding.any?

      scope = scope.for_owners(options.owners.map(&:id)) if options.owners
      scope = scope.exclude_owners(options.exclude_owners_by_id) if options.exclude_owners_by_id.present?

      scope = scope.for_authors(options.authors.map(&:id)) if options.authors

      # Scopes for new filters in Hyperlist
      #
      # N.b. these scopes are temporary and are planned to be deprecated in the near future as soon as
      # the new notifications back-end is ready, isolating their usage purely to the Hyperlist client
      if options.focusing.present?
        scope = scope.focus(options.focusing)
      elsif options.team_mention.present?
        scope = scope.where(reason: "team_mention")
      elsif options.not_focus_team_mentioned.present?
        scope = scope.not_focus_team_mentioned(options.not_focus_team_mentioned)
      end

      scope
    end

    # Public: Returns all unread NotificationEntries until a given time for a user.
    #
    # time    - DateTime before the notifications were updated last.
    # user_id - The user_id to perform the operation against.
    # list    - Optional Newsies::List object to scope the operation against.
    #
    # Returns a NotificationEntry relation.
    def self.unread_before(time, user_id, list = nil)
      scope = NotificationEntry.for_user(user_id).updated_before(time).unread
      scope = scope.for_list(list) if list

      scope
    end

    # Logs timing and affected row count for a single execution of a clear method
    #
    # method_name - The method being timed
    # elapsed_ms - Runtime of the method in milliseconds
    # affected_rows_count - How many rows were affected
    # opts - optional options hash
    #
    # Returns nothing.
    def self.log_timing_and_count(method_name, elapsed_ms, affected_rows_count, opts = {})
      GitHub.dogstats.timing(
        "newsies.mysql_web_indexer." + method_name,
        elapsed_ms,
        opts)
      # Log metric for total rows affected by the query in the loop
      GitHub.dogstats.histogram(
        "newsies.mysql_web_indexer." + method_name + ".affected_rows",
        affected_rows_count)
    end

    # Internal: Builds a key to identify the thread in thread subscriptions.
    #
    # list   - The List object.
    # thread - The Thread object.
    #
    # Returns a String key.
    def self.to_thread_key(list, thread)
      newsies_thread = Newsies::Thread.to_object(thread)
      "%d;%s;%s" % [list.id, newsies_thread.type, newsies_thread.id]
    end

    # Internal: Normalizes a Summary object into a Summary Hash.
    #
    # summary - Either a Summary object responding to #to_summary_hash, or a
    #           Hash.
    #
    # Returns the Hash of the Summary data.
    def self.normalize_summary(summary)
      if summary.respond_to?(:to_summary_hash)
        summary.to_summary_hash
      else
        summary
      end
    end

    # Internal: Extracts the List ID and String Thread key from a Summary.
    #
    # summary - A Hash of the Summary details.
    #
    # Returns an Array of the Integer List ID and a String Thread key.
    def self.summary_to_list_and_thread_keys(summary)
      list_type = summary[:list][:type]
      list_id = summary[:list][:id]
      thread_key = "%d;%s;%s" % [list_id,
        summary[:thread][:type], summary[:thread][:id]]
      [list_type, list_id, thread_key]
    end

    # Helper method to provide a common interface with SavedNotificationEntry
    # that is used to created "summary" hashes.
    #
    def reason
      super || ""
    end

    # Dummy method to provide a common interface with SavedNotificationEntry
    # that is used to created "summary" hashes.
    #
    def mentioned
      reason == "mention"
    end

    # Public: Generate a summary_hash, which combines the rollup summary with user specific
    # information from this notification entry
    def to_summary_hash
      return nil unless notification_summary

      notification_summary&.to_summary_hash.merge({
        unread:       unread?,
        archived:     archived?,
        reason:       reason,
        mentioned:    mentioned || false,
        important:    false,
        last_read_at: last_read_at,
        last_updated_at: updated_at,
        notification_entry_id: id,
      })
    end

    # Public: returns the Newsies::Thread object for this notification entry
    def newsies_thread
      (_, thread_type, thread_id) = thread_key.split(";")
      @newsies_thread ||= Newsies::Thread.new(thread_type, thread_id, list: newsies_list)
    end

    # Public: returns the Newsies::List object for this notification entry
    def newsies_list
      @newsies_list ||= Newsies::List.new(list_type, list_id)
    end

    def flipper_id
      GitHub::FlipperActor.to_flipper_id(User, user_id)
    end
  end
end
