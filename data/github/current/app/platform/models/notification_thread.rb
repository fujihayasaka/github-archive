# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  LIMIT_ACTIONS_PER_USER = 50

  include GitHub::Relay::GlobalIdentification
  include GitHub::Memoizer

  attr_reader :notification_entry, :user

  class InvalidPermalinkURIError < StandardError; end

  # Public: Initialize a Platform::Models::NotificationThread model. This object
  # backs the Platform::Objects::NotificationThread object used in the GraphQL API.
  #
  # notification_entry - A summarized notification entry hash returned from Newsies.
  #
  # Examples
  #
  #   notification_thread = GitHub.newsies.web.all(user).first
  #   Platform::Models::NotificationThread.new(notification_thread, user: user)
  def initialize(notification_entry, user:, starred: false)
    @user = user
    @notification_entry = notification_entry
    @starred = starred
  end

  def async_target_for_conditional_access
    async_list.then { |list| list.try(:async_target_for_conditional_access) }
  end

  def readable_by?(viewer)
    async_readable_by?(viewer).sync
  end

  def async_readable_by?(viewer, unauthorized_account_ids: [])
    return Promise.resolve(false) unless viewer && viewer.id == user.id

    Promise.all([
      async_list,
      async_thread,
      async_subject,
      async_in_unauthorized_account?(unauthorized_account_ids),
    ]).then do |list, thread, subject, in_unauthorized_account|
      next false if in_unauthorized_account

      unless list && thread && subject
        cleanup_for(viewer)
        next false
      end

      # Not all threads implement async_hide_from_user? so fallback to not-hidden by default
      async_hide_thread_from_user = thread.try(:async_hide_from_user?, viewer) || Promise.resolve(false)

      Promise.all([
        thread.async_readable_by?(viewer),
        async_hide_thread_from_user,
      ]).then do |(readable, hidden)|
        next true if readable && !hidden

        # Cleanup notifications if inaccessible but _not_ if spammy
        cleanup_for(viewer) if !readable

        next false
      end
    end
  end

  # Public: a unique identifier for this notification thread. Used to generate
  # the legacy global_relay_id.
  def id
    "#{summary_id}:#{user.id}"
  end

  # Public: The summary_id of the notification entry.
  def summary_id
    notification_entry[:id]
  end

  # Public: The title of the notification thread.
  def title
    notification_entry[:title] || "No title"
  end

  memoize def list
    async_list.sync
  end

  # Public: The notification thread's parent association.
  #
  # Returns a Promise resolving to a Repository or Team.
  def async_list
    return @async_list if defined? @async_list

    # If the thread is for a private repo invite, our normal method of finding the repo won't work
    # because the user doesn't yet have access to it, until they accept the invite. This short-circuits the
    # ActiveRecord loader to directly return the record.
    @async_list = if thread_type == "RepositoryInvitation"
      Promise.resolve(Repositories::Public.find_active(list_id.to_i))
    else
      Platform::Loaders::ActiveRecord.load(list_type.constantize, list_id.to_i, security_violation_behaviour: :nil)
    end
  end

  def async_list_subscription
    Platform::Loaders::NewsiesListSubscription.load(user.id, newsies_list)
  end

  def async_thread_type_subscription
    async_newsies_thread.then do |thread|
      Platform::Loaders::NewsiesThreadTypeSubscription.load(user.id, thread)
    end
  end

  def async_thread_subscription
    if Notifyd::Flags.new(user).enable_issue_notifications?
      Promise.all([
        async_thread,
        async_list
      ]).then do |thread, list|
        Platform::Loaders::NotificationThreadSubscription.load(user, thread, list)
      end
    else
      async_newsies_thread.then do |thread|
        Platform::Loaders::NewsiesThreadSubscription.load(user.id, thread)
      end
    end
  end

  memoize def subscription_status
    async_subscription_status.sync
  end

  memoize def async_subscription_status
    Promise.all([
      async_list_subscription,
      async_thread_type_subscription,
      async_thread_subscription,
    ]).then do |list_subscription, thread_type_subscription, thread_subscription|
      # ignoring list overrides all
      next "list_ignored" if list_subscription&.ignored?

      if Notifyd::Flags.new(user).enable_issue_notifications? ? thread_subscription&.valid? : thread_subscription.present?
        next "unsubscribed" if thread_subscription.ignored?
        next "thread_subscribed"
      end

      next "thread_type_subscribed" if thread_type_subscription.present?
      next "list_subscribed" if list_subscription.present?

      # no subscriptions at all
      "unsubscribed"
    end
  end

  # Public: Is the notification in one of the listed unauthorized accounts?
  #
  # Returns a Promise of a Boolean
  def async_in_unauthorized_account?(unauthorized_account_ids)
    return Promise.resolve(false) unless unauthorized_account_ids.present?

    async_list
      .then { |list| list.try(:async_owner) || list.try(:async_organization) }
      .then do |owner|
        next false if owner.nil?

        unauthorized_account_ids.include?(owner.id)
      end
  end

  memoize def subject
    async_subject.sync
  end

  # Public: The subject of the notification thread.
  #
  # Returns a Promise.
  memoize def async_subject
    if pull_request?
      async_thread.then { |issue| issue&.async_pull_request }
    else
      async_thread
    end
  end

  # Public: Has the user seen the most recent update to the notification thread?
  #
  # Returns a Boolean.
  def unread?
    notification_entry[:unread]
  end

  # Public: Has the notification entry been archived?
  #
  # Returns a Boolean.
  def archived?
    notification_entry[:archived]
  end

  # Public: When did the user last read the notification thread?
  def last_read_at
    notification_entry[:last_read_at]
  end

  # Public: Why is the user receiving notifications about this subject?
  def reason
    reason = notification_entry[:reason]
    if reason.blank?
      "subscribed"
    else
      reason
    end
  end

  memoize def recent_participants
    async_recent_participants.sync
  end

  # Public: Get the 3 most recent participants on the thread.
  memoize def async_recent_participants
    async_thread.then do |thread|
      participant_ids = sorted_items.map { |item| item["user_id"] }
      participant_ids.unshift(thread.try(:user_id))
      participant_ids.compact!
      participant_ids.reverse!
      participant_ids.uniq!
      participant_ids.reverse!
      Platform::Loaders::ActiveRecord.load_all(::User, participant_ids.last(3)).then do |users|
        users.compact.reject do |participant|
          next false unless GitHub.spamminess_check_enabled?
          next false if participant.id == user.id

          participant.spammy?
        end
      end
    end
  end

  # Public: The author of the thread's summary item which will be the first
  # unread item or the latest item.
  def summary_item_author
    if summary_item && summary_item["user_id"].present?
      Platform::Loaders::ActiveRecord.load(::User, summary_item["user_id"])
    end
  end

  # Public: The body of the thread's summary item which will be the first unread
  # item or the latest item.
  def summary_item_body
    if summary_item
      summary_item["body"]
    end
  end

  # Public: For a CheckSuite, the conclusion of that CheckSuite.
  def check_suite_summary_conclusion
    notification_entry[:check_suite_conclusion] if thread_type == "CheckSuite"
  end

  # Public: Get the number of unread items on the thread.
  def unread_items_count
    sorted_items.count { |item| item_unread?(item) }
  end

  # Public: The timestamp at which the notification thread was last summarized.
  def last_summarized_at
    notification_entry[:updated_at] || Time.now.utc
  end

  # Public: The timestamp at which the most recent notification was received for the current user.
  def last_updated_at
    notification_entry[:last_updated_at]
  end

  # Public: Checks if NotificationThread has saved notification entry
  def starred?
    @starred
  end

  alias :is_starred :starred?

  # Public: The class name of the thread's parent association.
  #
  # Returns a String.
  def list_type
    notification_entry[:list][:type]
  end

  # Public: The id of the thread's parent association.
  #
  # Returns a String.
  def list_id
    notification_entry[:list][:id]
  end

  # Public: The class name of the thread.
  #
  # Returns a String.
  def thread_type
    notification_entry[:thread][:type]
  end

  # Public: The id of the notification thread. If the thread is a Commit, the
  # thread_id will be the commit's oid.
  #
  # Returns a String.
  def thread_id
    notification_entry[:thread][:id]
  end

  def last_comment_type
    return last_item["type"] if last_item.present?
    # If there is no last item, just use the thread itself as the "last comment"
    thread_type
  end

  def last_comment_id
    return last_item["id"] if last_item.present?
    # If there is no last item, just use the thread as the "last comment"
    thread_id
  end

  # Public: The notification entry's thread object.
  #
  # Returns a Promise.
  def async_thread
    return @async_thread if defined? @async_thread

    @async_thread = case thread_type
    when "Grit::Commit"
      async_list.then do |repository|
        next unless repository

        Platform::Loaders::GitObject.load(repository, thread_id, expected_type: :commit)
      end
    when "RepositoryDependabotAlertsThread"
      async_list.then do |repository|
        next unless repository

        RepositoryDependabotAlertsThread.new(repository)
      end
    else
      Platform::Loaders::ActiveRecord.load(thread_type.constantize, thread_id.to_i)
    end
  end

  def oldest_unread_item_anchor
    return unless oldest_unread_item && oldest_unread_item["permalink"].present?
    uri = URI(oldest_unread_item["permalink"])

    uri.fragment
  rescue URI::InvalidURIError
    # It's possible that the permalink is not a valid url.
    # To prevent exceptions we just catch and log errors for cases like these so we can fix them
    newsies_thread = async_newsies_thread.sync
    NotificationsFailbot.report(
      InvalidPermalinkURIError.new("Invalid permalink URI in thread of type #{thread_type}"),
      "gh.notifications.list.id": newsies_list.id,
      "gh.notifications.list.type": newsies_list.type,
      "gh.notifications.thread.id": newsies_thread.id,
      "gh.notifications.thread.type": newsies_thread.type,
    )
  end

  memoize def url
    async_url.sync
  end

  memoize def async_url
    return Promise.resolve(summary_item["permalink"]) if summary_item && summary_item["permalink"]

    # Fallback to thread permalink if missing for some reason
    async_thread.then { |thread| thread.permalink }
  end

  def async_subscription_type
    async_newsies_thread.then(&:subscription_type)
  end

  def subscription_type
    return @subscription_type if defined? @subscription_type
    @subscription_type = async_subscription_type.sync
  end

  def sorted_items
    @sorted_items ||= notification_entry[:items]&.map do |(key, value)|
      type, id = key.split(":")
      value["type"] = type
      value["id"] = id
      value
    end&.sort do |a, b|
      a["created_at"].to_i <=> b["created_at"].to_i
    end
  end

  # Context: https://github.com/github/github/issues/125008
  sig { returns(T::Boolean) }
  def internal_only?
    thread_type == "RepositoryAdvisory" || thread_type == "AdvisoryCredit"
  end

  private

  def cleanup_for(viewer)
    GitHub.newsies.async_cleanup_inaccessible_thread_for_user(viewer.id, list_type, list_id, thread_type, thread_id)
  end

  def newsies_list
    @newsies_list ||= ::Newsies::List.new(list_type, list_id.to_i)
  end

  def async_newsies_thread
    async_thread.then do |thread|
      Newsies::Thread.to_object(thread, list: newsies_list)
    end
  end

  def item_unread?(item)
    return false if item["user_id"] == @user.id
    return true if last_read_at.blank?
    last_read_at.to_i < item["created_at"].to_i
  end

  def oldest_unread_item
    return @oldest_unread_item if defined? @oldest_unread_item
    @oldest_unread_item = sorted_items.find { |item| item_unread?(item) }
  end

  def summary_item
    return @summary_item if defined? @summary_item
    @summary_item = oldest_unread_item || last_item
  end

  def last_item
    sorted_items.last
  end

  # Internal: Is the subject of the notification a pull request?
  #
  # Returns a Boolean.
  def pull_request?
    notification_entry[:is_pull_request]
  end
end
