# typed: false
# frozen_string_literal: true

require "newsies/options"
require "newsies"

module Newsies
  # Responsible for querying newsies data from NotificationsController.
  # loaded in GitHub.newsies.web
  class Web

    include GitHub::Tracing
    trace_method :async_mark_all_notifications_as_read
    trace_method :create_custom_inbox
    trace_method :destroy_custom_inbox
    trace_method :find_rollup_summary_by_thread
    trace_method :mark_all
    trace_method :mark_all_from_query
    trace_method :mark_all_notifications_as_read
    trace_method :mark_summaries_as_archived
    trace_method :mark_summaries_as_read
    trace_method :mark_summaries_as_unread
    trace_method :mark_summary_archived
    trace_method :mark_summary_read
    trace_method :mark_summary_unread
    trace_method :mark_thread_read
    trace_method :save_thread
    trace_method :saved_summary_hash_from_summary_id
    trace_method :unsave_thread
    trace_method :update_custom_inbox
    trace_method :update_rollup_summary

    REPOSITORY_CLASS_NAME = "Repository".freeze
    TEAM_CLASS_NAME = "Team".freeze

    # Public: Retrieves a collection of web notifications for the user.
    #
    # Returns a Newsies::Responses::Array instance containing Hashes of
    # decorated NotificationSummary#to_summary_hash objects.
    def all(user, options = {})
      Responses::Array.new do
        summary_hashes_from_notification_entries(
          NotificationEntry.for_user_with_options(user.id, team_aware_options_from(options)),
        )
      end
    end

    # Public: Retrieves a collection of saved web notifications for the user.
    #
    # Returns a Newsies::Responses::Array instance containing Hashes of
    # decorated NotificationSummary#to_summary_hash objects.
    def all_saved(user, options = {})
      Responses::Array.new do
        summary_hashes_from_notification_entries(
          SavedNotificationEntry.get(user_id: user.id, options: options),
        )
      end
    end

    # Public: Retrieves a summary hash by the user and summary id.
    #
    # Returns a Newsies::Response instance containing a decorated NotificationSummary#to_summary_hash object.
    def summary_hash_from_summary_id(user, summary_id)
      Response.new do
        summary_hashes_from_notification_entries(
          NotificationEntry.for_user(user.id).for_summary(summary_id),
        ).first
      end
    end

    # Public: Retrieves a summary hash by the user and summary id for a saved notification entry if it exists
    #
    # Returns a Newsies::Response instance containing a decorated NotificationSummary#to_summary_hash object.
    def saved_summary_hash_from_summary_id(user, summary_id)
      Response.new do
        summary_hashes_from_notification_entries(
          SavedNotificationEntry.for_user(user.id).where(summary_id: summary_id),
        ).first
      end
    end

    # Public: Retrieves a collection of web notifications by user, notification entry ids and filters them by status
    # Requires an offset and limit as a :fingers_crossed: _temporary_ solution to the fact that we can't
    # filter by status via ES but after-the-fact using MySQL.
    #
    # Returns a Newsies::Responses::Array instance containing Hashes of
    # decorated NotificationSummary#to_summary_hash objects.
    def all_by_notification_entry_ids_and_statuses(user, notification_entry_ids, statuses, offset:, limit:)
      Responses::Array.new do
        summary_hashes_from_notification_entries(
          NotificationEntry.for_user(user.id).where(id: notification_entry_ids, status: statuses)
                                             .order(updated_at: :desc)
                                             .offset(offset).limit(limit)
        )
      end
    end

    # Public: Retrieves a collection of saved web notifications for the user and summary ids.
    #
    # Returns a Array of NotificationSummary ids.
    def all_saved_by_summary_ids(user, summary_ids)
      Responses::Array.new do
        if summary_ids.blank?
          []
        else
          SavedNotificationEntry.get_by_summary_ids(user_id: user.id, summary_ids: summary_ids)
        end
      end
    end

    # Public: Retrieves a summary hash by the user and thread.
    #
    # Returns a Newsies::Response instance containing a decorated NotificationSummary#to_summary_hash object.
    def by_thread(user, thread)
      newsies_list = Newsies::List.to_object(thread.notifications_list)
      newsies_thread = Newsies::Thread.to_object(thread, list: newsies_list)

      Response.new do
        summary_hashes_from_notification_entries(
          NotificationEntry.for_user(user.id).for_thread(newsies_thread),
        ).first
      end
    end

    # Public
    # Returns Newsies::Responses::Count instance.
    def count(user, options = {})
      Responses::Count.new do
        NotificationEntry.count(user.id, team_aware_options_from(options))
      end
    end

    # Public: Counts the number of saved notifications for the user.
    #
    # Returns a Newsies::Responses::Count instance.
    def count_saved(user, options = {})
      Responses::Count.new do
        SavedNotificationEntry.count(user_id: user.id, options: options)
      end
    end

    # Public
    # Returns Newsies::Responses::Boolean instance.
    def exist(user, options = {})
      Responses::Boolean.new do
        NotificationEntry.exist?(user.id, team_aware_options_from(options))
      end
    end

    # Returns Newsies::Responses::Array instance.
    #
    # user    - The User to count notifications for.
    # options - Optional hash to further filter the query.
    #           See Newsies::Web::FilterOptions.
    #
    # Returns Newsies::Responses::Array of Arrays
    #
    # Each element of the array is of the form:
    #
    # [ list, count, unread_count]
    #
    #   - list:         List object (Repository or Team)
    #   - count:        count of notifications for the list, that match the passed `options` filters
    #   - unread_count: count of _unread_ notifications for the list, that also match the passed `options` filters
    def counts_by_list(user, options = {})
      Responses::Array.new do
        final_options = team_aware_options_from(options)
        count_rows = NotificationEntry.counts_by_list(user.id, final_options)

        rows_by_list_type = count_rows.group_by(&:first)
        team_ids = rows_by_list_type[TEAM_CLASS_NAME]&.map(&:second) || []
        repo_ids = rows_by_list_type[REPOSITORY_CLASS_NAME]&.map(&:second) || []

        teams_by_id = Team.where(id: team_ids).index_by(&:id)
        repos_by_id = Repository.includes(:owner).where(id: repo_ids).index_by(&:id)

        count_rows.reduce([]) do |memo, (list_type, list_id, count_all, count_unread)|
          list = (list_type == REPOSITORY_CLASS_NAME ? repos_by_id : teams_by_id)[list_id]
          memo << [list, count_all, count_unread] if list
          memo
        end
      end
    end

    # Public
    # Returns Newsies::Responses::Array instance.
    def by_conversations(user, subjects)
      Responses::Array.new do
        if subjects.blank?
          []
        else
          index = subjects.index_by { |subject| subject.id.to_s }
          threads = subjects.map do |subject|
            list = Newsies::List.new(REPOSITORY_CLASS_NAME, subject.repository_id)
            [list, subject]
          end

          response = notifications_by_user_and_threads(user, threads)
          raise response.error if response.failed?

          notification_entries = response.value
          notification_entries.map do |entry|
            if (!block_given? || yield(entry)) &&
              entry.thread_key =~ /;(\d+)$/
              index[$1]
            end
          end.compact
        end
      end
    end

    # Public
    def by_summaries(user, summaries)
      Responses::Array.new do
        threads = Array(summaries).map(&:newsies_thread)
        NotificationEntry.for_user_and_threads(user.id, threads)
      end
    end

    # Public: Marks a group of notifications for a particular user as read.
    #
    # time - DateTime timestamp before which to mark notifications as read (prevents us from
    #        accidentally marking newer things as read).
    # user - User for which to mark notifications as read.
    # list - Optional list object (e.g. Repository) for which to mark notifications as read. If
    #        omitted, this will mark all notifications for the user as read across list types.
    #
    # Returns Newsies::Response instance.
    def mark_all(time, user, list = nil)
      Response.new do
        if list
          newsies_list = Newsies::List.to_object(list)
          NotificationEntry.mark_all(time, user.id, newsies_list)
        else
          NotificationEntry.mark_all(time, user.id)
        end
      end
    end

    # Public: enqueues a background job to mark all notifications that match the
    # query generated from `filter_options` with the `state` provided.
    #
    # Supports read, unread, and archived. Updates in batches.
    #
    # user            - user for which to mark notifications as read
    # state           - status to mark all notifications as
    # filter_options  - options for refining NotificationEntry scope, defaults:
    #                   - before: time right meow
    #                   - statuses: `[:unread]`
    def mark_all_from_query(user, state, filter_options)
      Responses::Boolean.new do
        # Don't set states that don't exist!
        return false unless [:read, :unread, :archived].include?(state)

        # Limit us to a subset of supported filterable attributes
        valid_filters = [:authors, :before, :owners, :statuses, :reasons, :lists, :thread_types]

        filter_options = filter_options.deep_dup
        filter_options.delete_if { |filter, _value| !valid_filters.include?(filter) }

        # No matter what, we require a point-in-time to query from.
        # If a value is not provided, we set one to be prevent sadness.
        filter_options[:before] = Time.now.utc if filter_options[:before].nil?

        # Transform v2 statuses to valid model statuses, removing invalid statuses
        if filter_options[:statuses]
          filter_options[:statuses].map! do |status|
            NotificationEntry::V2_STATE_TO_INTERNAL_STATE[status]
          end.compact!
        else
          # Default to unread to save our poor baby DB
          filter_options[:statuses] = [:inbox_unread]
        end

        MarkAllNotificationsFromQueryJob.perform_later(user.id, state, filter_options)
      end
    end

    # Public: Optimistically marks notifications as read.
    #         If there are too many unread notifications, the database is busy
    #         or Newsies is not available, an async background job will be enqueued
    #         to mark all notifications as read.
    #
    #
    # time - DateTime timestamp before which to mark notifications as read (prevents us from
    #        accidentally marking newer things as read).
    # user - User for which to mark notifications as read.
    # list - Optional list object (e.g. Repository) for which to mark notifications as read. If
    #        omitted, this will mark all notifications for the user as read across list types.
    #
    # Returns a Responses::Boolean. True if the notifications were synchronously marked as read
    # or false if a background job has been enqueued to mark the notifications as read.
    def mark_all_notifications_as_read(time, user, list = nil)
      Responses::Boolean.new do
        newsies_list = Newsies::List.to_object(list) if list

        scope = NotificationEntry.unread_before(time, user.id, newsies_list)
        unread_count = scope.limit(MarkAllNotificationsAsReadJob::BATCH_SIZE + 1).count
        if unread_count > MarkAllNotificationsAsReadJob::BATCH_SIZE
          stats_key = "newsies.web.mark_all_notifications_as_read.too_many_notifications"
          GitHub.dogstats.increment(stats_key, tags: ["list_typle:#{newsies_list&.type}"])
          async_mark_all_notifications_as_read(time, user, list)
          next false
        end

        # `perform_now` will catch and return expected errors before retrying the job
        # see
        # https://github.com/rails/rails/blob/c11d115fa3c58ec6bde5e9799673cee381d22d47/activejob/lib/active_job/execution.rb#L42
        # and
        # https://github.com/rails/rails/blob/c11d115fa3c58ec6bde5e9799673cee381d22d47/activesupport/lib/active_support/rescuable.rb#L93
        retry_error = MarkAllNotificationsAsReadJob.perform_now(user.id, time, newsies_list&.type, newsies_list&.id)
        !retry_error
      end
    end

    # Public: Enqueues a job to mark notifications for a particular user as read.
    #
    # time - DateTime timestamp before which to mark notifications as read (prevents us from
    #        accidentally marking newer things as read).
    # user - User for which to mark notifications as read.
    # list - Optional list object (e.g. Repository) for which to mark notifications as read. If
    #        omitted, this will mark all notifications for the user as read across list types.
    #
    # Returns nothing.
    def async_mark_all_notifications_as_read(time, user, list = nil)
      newsies_list = Newsies::List.to_object(list) if list
      list_type = newsies_list.type if newsies_list
      list_id = newsies_list.id if newsies_list

      MarkAllNotificationsAsReadJob.perform_later(user.id, time, list_type, list_id)

      nil
    end

    # Public: Marks summaries as read for the given User.
    #
    # user        - The User.
    # summary_ids - Array of NotificationSummary ids.
    #
    # Returns Newsies::Response instance with no value.
    def mark_summaries_as_read(user, summary_ids)
      Response.new do
        summaries = NotificationSummary.where(id: Array(summary_ids)).to_a
        mark_summary_read(user, *summaries) unless summaries.empty?
      end
    end

    # Public: Marks one or more Summary objects as read for the given User.
    #
    # user       - The current User.
    # *summaries - One or more NotificationSummary objects.
    #
    # Returns Newsies::Response instance with no value.
    def mark_summary_read(user, *summaries)
      response = Response.new do
        NotificationEntry.mark_summaries(:read, user.id, summaries.map(&:id).compact.uniq)
        nil
      end

      web_socket_notify(user, summaries) if response.success?
      response
    end

    def mark_summaries_as_archived(user, summary_ids)
      Response.new do
        summaries = NotificationSummary.where(id: summary_ids).to_a
        mark_summary_archived(user, *summaries) unless summaries.empty?
      end
    end

    def mark_summary_archived(user, *summaries)
      response = Response.new do
        NotificationEntry.mark_summaries(:archived, user.id, summaries.map(&:id).compact.uniq)
        nil
      end

      web_socket_notify(user, summaries) if response.success?
      response
    end

    # Public: Marks one or more threads as viewed for the given User.
    #
    # user   - The current User.
    # thread - The thread.
    #
    # Returns Newsies::Response instance with no value.
    def mark_thread_read(user, thread)
      newsies_list = Newsies::List.to_object(thread.notifications_list)
      newsies_thread = Newsies::Thread.to_object(thread, list: newsies_list)

      response = Response.new do
        NotificationEntry.mark_thread(:read, user.id, newsies_thread)
        nil
      end

      web_socket_notify(user, [thread]) if response.success?
      response
    end

    # Public: Marks summaries as unread for the given User.
    #
    # user        - The User.
    # summary_ids - Array of NotificationSummary ids.
    #
    # Returns Newsies::Response instance with no value.
    def mark_summaries_as_unread(user, summary_ids)
      Response.new do
        summaries = NotificationSummary.where(id: summary_ids).to_a
        mark_summary_unread(user, *summaries) unless summaries.empty?
      end
    end

    # Public: Marks one or more Summary objects as unread for the given User.
    #
    # user       - The current User.
    # *summaries - One or more NotificationSummary objects.
    #
    # Returns Newsies::Response with no value.
    def mark_summary_unread(user, *summaries)
      Response.new do
        NotificationEntry.mark_summaries(:unread, user.id, summaries.map(&:id).compact.uniq)
        web_socket_notify(user, summaries)
        nil
      end
    end

    # Public: X marks the spot.
    #
    # user - The current User.
    # summary - A NotificationSummary instance.
    #
    # Returns Newsies::Response instance.
    def delete(user, summary)
      Response.new do
        NotificationEntry.delete(user.id, summary.id)
        if summary.newsies_thread
          # Removes a saved thread record for the user and summary if one exists.
          SavedNotificationEntry.destroy(user_id: user.id, list: summary.newsies_list, thread: summary.newsies_thread)
        end
      end
    end

    # Public: Deletes a saved notification thread for the user.
    #
    # user - The user that the saved notification thread belongs to.
    # thread - The thread object that the notification summarizes.
    def unsave_thread(user, thread)
      unless thread.is_a?(Newsies::Thread)
        list = Newsies::List.to_object(thread.notifications_list)
        thread = Newsies::Thread.to_object(thread, list: list)
      end

      Response.new do
        SavedNotificationEntry.destroy(user_id: user.id, list: thread.list, thread: thread)
      end
    end

    # Public: Returns the Integer number of results per page.
    def per_page
      NotificationEntry.per_page
    end

    # Public: Adds a thread to a user's saved notification list.
    #
    # user - The User that the saved notification will be belong to.
    # thread - The thread that the notification will summarize.
    def save_thread(user, thread)
      unless thread.is_a?(Newsies::Thread)
        list = Newsies::List.to_object(thread.notifications_list)
        thread = Newsies::Thread.to_object(thread, list: list)
      end

      summary = find_rollup_summary_by_thread(thread.list, thread)

      Response.new do
        SavedNotificationEntry.save(user_id: user.id, summary_id: summary.id,
          list: thread.list, thread: thread)
      end
    end

    # Returns all CustomInbox objects belonging to the given user.
    def all_custom_inboxes(user_id)
      Responses::Array.new do
        CustomInbox.default_filters(user_id) + CustomInbox.where(user_id: user_id).order(id: :asc).all
      end
    end

    # Returns an new CustomInbox object or nil if it does not exist.
    def get_custom_inbox(id)
      Response.new { CustomInbox.find_by_id(id) }
    end

    # Returns a new CustomInbox object, which may or may not have been persisted.
    def create_custom_inbox(user_id:, name:, query_string:)
      Response.new { CustomInbox.create(user_id: user_id, name: name, query_string: query_string) }
    end

    # Returns the updated CustomInbox object, which may or may not have actually
    # been updated, or nil if it doesn't exist.
    def update_custom_inbox(id:, **kwargs)
      Response.new do
        begin
          CustomInbox.update(id, **kwargs.slice(:name, :query_string).compact)
        rescue ActiveRecord::RecordNotFound
        end
      end
    end

    # Returns destroyed CustomInbox object, which may or may not have actually
    # been destroyed, or nil if it doesn't exist.
    def destroy_custom_inbox(id)
      Response.new do
        begin
          CustomInbox.destroy(id)
        rescue ActiveRecord::RecordNotFound
        end
      end
    end

    # Internal
    # Returns Responses::Array instance containing NotificationEntry instances.
    def notifications_by_user_and_threads(user, lists_and_threads)
      Responses::Array.new do
        threads = lists_and_threads.map do |(list, thread)|
          newsies_list = Newsies::List.to_object(list)
          Newsies::Thread.to_object(thread, list: newsies_list)
        end
        NotificationEntry.for_user_and_threads(user.id, threads)
      end
    end

    # Returns a Newsies::Response wrapping a NotificationEntry
    def notification(user, list, thread)
      Response.new do
        notifications_by_user_and_threads(user, [[list, thread]]).first
      end
    end

    # DUPE
    # Internal: Loads the Repositories for the given IDs, eager loaded with the
    # owner.
    #
    # ids - An Array of Integer IDs.
    #
    # Returns a Hash of Integer Repository ID => Repository.
    def indexed_repositories_by_ids(ids)
      Repository.includes(:owner).where(id: ids).index_by { |r| r.id }
    end

    def find_or_create_rollup_summary_from_list_thread_comment(list, thread, comment)
      Response.new do
        NotificationSummary.fetch_and_update!(list, thread, comment)
      end
    end

    def rollup_summary_from_repository_invitation(invitation)
      Response.new do
        NotificationSummary.fetch_and_update!(invitation.repository, invitation, invitation)
      end
    end

    # Public: Finds a rollup summary by id.
    #
    # Returns Newsies::Response instance.
    def find_rollup_summary(id)
      Response.new do
        NotificationSummary.find(id)
      end
    end

    def find_rollup_summary_by_id(id)
      Response.new do
        NotificationSummary.find_by_id(id)
      end
    end

    # Public: Loads the NotificationSummary objects for given IDs
    #
    # ids - An Array of Integer IDs.
    #
    # Returns a Newsies::Responses::Array instance containing NotificationSummary instances.
    def find_rollup_summaries_by_ids(ids)
      Responses::Array.new do
        NotificationSummary.where(id: ids)
      end
    end

    # Public: Finds an existing Summary for the given list and thread.
    #
    # list    - Usually a Repository.
    # thread  - An Issue or Commit.

    # Returns Newsies::Response instance.
    def find_rollup_summary_by_thread(list, thread)
      Response.new do
        NotificationSummary.by_thread(list, thread)
      end
    end

    # Public: Update a rollup summary
    #
    # summary - an instance of NotificationSummary
    # issue_event - in instance of IssueEvent to update summary with
    #
    # Returns Newsies::Response instance.
    def update_rollup_summary(summary, issue_event)
      return unless summary && issue_event
      Response.new do
        summary.issue_state = IssueEvent.summary_state_for_event(issue_event)
        summary.save!
      end
    end

    # Internal.
    #
    # If necessary, this augments the given options with a key that triggers proper handling of
    # DiscussionPost and DiscussionPostReply notifications in NotificationEntry#add_where_clause_to.
    # (which gets called from each of the following methods in this class: `ids`, `exist`, `count`
    # and `count_all`).
    def team_aware_options_from(options)
      if options[:list].is_a?(Team)
        generic_options = options.clone
        generic_options[:thread_type] = "DiscussionPost"
        generic_options
      else
        options
      end
    end

    def to_thread_key(list, thread)
      NotificationEntry.to_thread_key(list, thread)
    end

    private

    # Private: Converts a list of (Saved)NotificationEntry objects into a list
    # of "summary" hashes that contain user-specific information about each
    # notification.
    #
    # notification_entries_scope - (Saved)NotificationEntries scope.
    #
    # Returns Array of "summary" Hashes
    def summary_hashes_from_notification_entries(notification_entries_scope)
      notification_entries = notification_entries_scope.includes(:notification_summary)

      summary_hashes = notification_entries.map do |notification_entry|
        unless notification_entry.notification_summary
          GitHub.dogstats.increment("newsies.cleanup.notification_summary_missing", tags: ["method:summary_hashes_from_notification_entries"])
          if GitHub.flipper[:notifications_summaries_recover_for_user].enabled?(notification_entry)
            RecoverNotificationSummariesForUserJob.perform_later(user_id: notification_entry.user_id)
          elsif GitHub.flipper[:notifications_summaries_recover].enabled?(notification_entry)
            newsies_list = Newsies::List.to_object(notification_entry.newsies_list)
            newsies_thread = Newsies::Thread.to_object(notification_entry.newsies_thread)
            RecoverNotificationSummaryJob.perform_later(
              id: notification_entry.summary_id,
              list_type: newsies_list.type,
              list_id: newsies_list.id,
              thread_type: newsies_thread.type,
              thread_id: newsies_thread.id,
            )
          else
            # skip and queue a cleanup job if notification summary is missing
            # ensure_thread_deleted: true means the job will double-check
            # the thread object is also deleted
            GitHub.newsies.async_delete_all_for_thread(
              notification_entry.newsies_list,
              notification_entry.newsies_thread,
              ensure_thread_deleted: true,
            )
          end

          next
        end

        notification_entry.to_summary_hash
      end
      summary_hashes.compact
    end

    def web_socket_notify(user, objects)
      objects.each do |object|
        if object.respond_to?(:sync_thread_read_state)
          object.sync_thread_read_state(user)
        end
      end
      user.notify_web_notifications_changed_socket_subscribers(NotificationEntry.default_live_updates_wait)
    end

    FilterOptions = ::Newsies::Options.new(
      :authors,
      :before,
      :count_limit,
      :excluding,
      :exclude_owners_by_id,
      :list_type,
      :list,
      :lists,
      :owners,
      :not_spam,
      :offset,
      :page,
      :participating,
      :per_page,
      :saved,
      :since,
      :thread_type,
      :thread_types,
      :unread,
      :reasons,
      :read,
      :statuses,

      # The below filters are temporary intended only for Hyperlist,
      # they will be removed once Hyperlist is fully migrated to the
      # new notification back-end system.
      :focusing,
      :team_mention,
      :not_focus_team_mentioned
    ) do

      def all?(*keys)
        keys.all? { |key| self[key] }
      end

      def since_time
        @since_time ||= time(since)
      end

      def before_time
        @before_time ||= time(before)
      end

      def time(time)
        case time
        when nil then nil
        when Time then time
        when Integer, /^\d+$/ then Time.at(time.to_i)
        else Time.parse(time.to_s)
        end
      end

      def page
        @page ||= [self[:page].to_i, 1].max
      end

      def per_page
        self[:per_page] || Newsies::NOTIFICATIONS_PER_PAGE
      end

      def offset
        self[:offset] || (page - 1) * per_page
      end

      def excluding
        Array(self[:excluding])
      end
    end
  end
end
