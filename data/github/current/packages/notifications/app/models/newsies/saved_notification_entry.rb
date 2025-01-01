# typed: true
# frozen_string_literal: true

module Newsies
  # Responsible for managing "saved" web notifications.
  class SavedNotificationEntry < ApplicationRecord::Domain::NotificationsEntries
    include GitHub::VexiActor

    self.utc_datetime_columns = [:created_at]
    self.record_timestamps = false

    belongs_to :notification_summary, class_name: "NotificationSummary", foreign_key: "summary_id" # rubocop:todo Rails/InverseOf

    scope :for_user, ->(user_id) {
      raise ArgumentError, "user_id cannot be nil" unless user_id
      where(user_id: user_id)
    }

    scope :for_users, ->(user_ids) {
      raise ArgumentError, "user_id cannot be nil" unless user_ids
      where(user_id: user_ids)
    }

    scope :for_list, ->(list) {
      raise ArgumentError, "list cannot be nil" unless list
      where(list_type: list.type, list_id: list.id)
    }

    # Entries for multiple lists, may be of different list_types
    scope :for_lists, ->(lists) {
      raise ArgumentError, "lists cannot be nil" unless lists
      where(where_condition_for_lists(lists))
    }

    scope :for_thread, ->(thread) {
      raise ArgumentError, "thread cannot be nil" unless thread
      where(thread_key: thread.key)
    }

    def flipper_id
      vexi_id
    end

    def vexi_id
      GitHub::VexiActor.to_feature_flag_id(User, user_id)
    end

    # Private: build a WHERE condition for multiple lists, with possibly different list_types
    # With multiple lists, we want to check `list_id IN (ids)`, but we must separate that
    # by list_type to ensure we get the right results
    #
    # Do not use directly, use via `for_lists` scope
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

    # Public: Inserts a saved notification for the user.
    #
    # user_id     - A user_id to perform the operation against.
    # summary_id  - An Integer id of the NotificationSummary.
    # list        - A Newsies::List instance.
    # thread      - A Newsies::Thread instance.
    #
    # Returns nothing.
    def self.save(user_id:, summary_id:, list:, thread:)
      attributes = {
        user_id:    user_id,
        summary_id: summary_id,
        list_id:    list.id,
        list_type:  list.type,
        thread_key: thread.key,
        created_at: Time.now.utc
      }

      upsert(attributes, on_duplicate: Arel.sql("created_at = VALUES(created_at)"))

      nil
    end

    # Public: Retrieves a set of saved notification for the user.
    #
    # user_id - A user_id to perform the operation against.
    #
    # Returns a scope of SavedNotificationEntry.
    def self.get(user_id:, options: {})
      options = Newsies::Web::FilterOptions.from(options)

      for_user(user_id)
      .order(:created_at)
      .limit(options.per_page)
      .offset(options.offset)
    end

    # Public: Retrieves a set of saved notification for the user by summary ids.
    #
    # user_id - A user_id to perform the operation against.
    # summary_ids - An Array of summary ids
    #
    # Returns an Array of summary ids or an empty Array if the user
    # has no saved notifications.
    def self.get_by_summary_ids(user_id:, summary_ids:)
      for_user(user_id)
      .where(summary_id: summary_ids)
      .pluck(:summary_id)
    end

    # Public: Counts saved notification for the user.
    #
    # user_id - A user_id to perform the operation against.
    #
    # Returns an Integer.
    def self.count(user_id:, options: {})
      ApproximateCount.new(for_user(user_id).count)
    end

    # Public: Deletes saved notification for the user.
    #
    # user_id - A user_id to perform the operation against.
    # list    - Optional: A Newsies::List instance used to filter the notifications.
    # thread  - Optional: Newsies::Thread instance used to filter the notifications.
    #
    # Returns nothing.
    def self.destroy(user_id:, list: nil, thread: nil)
      scope = for_user(user_id)
      if list
        scope = scope.for_list(list)
        scope = scope.for_thread(thread) if thread
      end

      scope.delete_all
      nil
    end

    # Public: Deletes saved notifications for all users from the list.
    #
    # list   - A List instance to clear threads for.
    #
    # Returns nothing.
    def self.destroy_list_set(list)
      scope = for_list(list)

      scope.delete_all
      nil
    end

    # Public: Deletes saved notifications for all users from the list and thread.
    #
    # list   - A List instance to clear threads for.
    # thread - A Thread instance to clear threads for.
    #
    # Returns nothing.
    def self.destroy_thread_set(list, thread)
      scope = for_list(list)
      scope = scope.for_thread(thread)

      scope.delete_all
      nil
    end

    # Dummy method to provide a common interface with NotificationEntry
    # that is used to created "summary" hashes.
    #
    def last_read_at
      created_at
    end

    # Dummy method to provide a common interface with NotificationEntry
    # that is used to created "summary" hashes.
    #
    def unread
      true
    end

    # Dummy method to provide a common interface with NotificationEntry
    # that is used to created "summary" hashes.
    #
    def reason
      "saved"
    end

    # Dummy method to provide a common interface with NotificationEntry
    # that is used to create "summary" hashes.
    #
    def mentioned
      false
    end

    # Public: Generate a summary_hash, which combines the rollup summary with user specific
    # information from this notification entry
    def to_summary_hash
      # if somehow the notification_summary is missing, this is an invalid notification entry
      return nil unless notification_summary

      notification_summary&.to_summary_hash.merge({
        unread:       unread,
        reason:       reason,
        mentioned:    mentioned,
        archived:     false,
        important:    false,
        last_read_at: last_read_at,
        last_updated_at: created_at,
      })
    end

    def newsies_thread
      @newsies_thread ||= Newsies::Thread.from_key(thread_key, list: newsies_list)
    end

    def newsies_list
      @newsies_list ||= Newsies::List.new(list_type, list_id)
    end
  end
end
