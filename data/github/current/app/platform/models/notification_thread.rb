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

  # Preload main data and relations
  def async_preload
    async_list.then do |list|
      async_subject.then do |subject|
        Promise.all(
          [
            async_subscription_status,
            async_title,
            async_url,
            async_recent_participants,
            list.is_a?(Repository) ? list.async_organization : nil,
            subject.is_a?(CheckSuite) ? subject.async_workflow_run : nil,
            subject.is_a?(Actions::WorkflowRun) ? subject.async_workflow : nil,
          ].compact
        ).then { self }
      end
    end
  end

  def async_target_for_conditional_access
    async_list.then { |list| list.try(:async_target_for_conditional_access) }
  end

  def readable_by?(viewer)
    async_readable_by?(viewer).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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
  #
  # The previous version of this ID included the summary_id and the user's ID, but
  # it has been deprecated
  def id
    "v2:#{composite_key}:#{user.id}"
  end

  memoize def composite_key
    Newsies::Thread.new(thread_type, thread_id, list: newsies_list).composite_key
  end

  # Public: The summary_id of the notification entry.
  def summary_id
    notification_entry[:summary_id] || notification_entry[:id]
  end

  # Public: The title of the notification thread.
  memoize def title
    async_title.sync
  end

  memoize def async_title
    async_info.then(&:async_title).then do |title|
      next title if title

      notification_entry[:title] || "No title"
    end
  end

  memoize def list
    async_list.sync
  end

  # Public: The notification thread's parent association.
  #
  # Returns a Promise resolving to a Repository or Team.
  memoize def async_list
    # If the thread is for a private repo invite, our normal method of finding the repo won't work
    # because the user doesn't yet have access to it, until they accept the invite. This short-circuits the
    # ActiveRecord loader to directly return the record.
    if thread_type == "RepositoryInvitation"
      Promise.resolve(Repositories::Public.find_active(list_id.to_i))
    else
      Platform::Loaders::ActiveRecord.load(list_type.constantize, list_id.to_i, security_violation_behaviour: :nil)
    end
  end

  memoize def async_list_subscription
    Platform::Loaders::NewsiesListSubscription.load(user.id, newsies_list)
  end

  memoize def async_thread_type_subscription
    async_newsies_thread.then do |thread|
      Platform::Loaders::NewsiesThreadTypeSubscription.load(user.id, thread)
    end
  end

  memoize def async_thread_subscription
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
    async_subscription_status.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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
    async_pull_request?.then do |is_pull_request|
      if is_pull_request
        async_thread.then { |issue| issue&.async_pull_request }
      else
        async_thread
      end
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
    async_recent_participants.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  # Public: Get the 3 most recent participants on the thread.
  memoize def async_recent_participants
    async_info.then(&:async_recent_participants).then do |participants|
      next participants unless participants.empty?

      async_thread.then do |thread|
        participant_ids = sorted_items.map { |item| item["user_id"] }
        participant_ids.unshift(thread.try(:user_id))
        participant_ids.compact!
        participant_ids.reverse!
        participant_ids.uniq!
        participant_ids.reverse!
        Platform::Loaders::ActiveRecord.load_all(::User, participant_ids.last(3))
      end
    end.then do |users|
      users.compact.reject do |participant|
        next false unless GitHub.spamminess_check_enabled?
        next false if participant.id == user.id

        participant.spammy?
      end
    end
  end

  # Public: The author of the thread's summary item which will be the first
  # unread item or the latest item.
  memoize def summary_item_author
    async_summary_item_author.sync
  end

  memoize def async_summary_item_author
    async_info.then(&:async_summary_item_author).then do |author|
      next author if author

      if summary_item && summary_item["user_id"].present?
        Platform::Loaders::ActiveRecord.load(::User, summary_item["user_id"])
      else
        Promise.resolve(nil)
      end
    end
  end

  # Public: The body of the thread's summary item which will be the first unread
  # item or the latest item.
  memoize def summary_item_body
    async_summary_item_body.sync
  end

  memoize def async_summary_item_body
    async_info.then(&:async_summary_item_body).then do |body|
      next body if body

      summary_item["body"] if summary_item
    end
  end

  # Public: For a CheckSuite, the conclusion of that CheckSuite.
  memoize def check_suite_summary_conclusion
    async_check_suite_summary_conclusion.sync
  end

  memoize def async_check_suite_summary_conclusion
    async_info.then(&:async_check_suite_conclusion).then do |conclusion|
      next conclusion if conclusion

      notification_entry[:check_suite_conclusion] if thread_type == "CheckSuite"
    end
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
  memoize def async_thread
    case thread_type
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
    when "AgentSessionThread"
      Platform::Loaders::ActiveRecord.load(AgentSessionFinishedNotification, thread_id.to_i).then do |notification|
        AgentSessionThread.new(notification) if notification
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
    newsies_thread = async_newsies_thread.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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
    async_info.then(&:async_url).then do |url|
      next url if url
      next summary_item["permalink"] if summary_item && summary_item["permalink"]

      # Fallback to thread permalink if missing for some reason
      async_thread.then { |thread| thread.permalink }
    end
  end

  memoize def async_subscription_type
    async_newsies_thread.then(&:subscription_type)
  end

  memoize def subscription_type
    async_subscription_type.sync
  end

  memoize def sorted_items
    notification_entry[:items]&.map do |(key, value)|
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

  sig { returns(T::Boolean) }
  def agent_session_thread?
    thread_type == "AgentSessionThread"
  end

  private

  def cleanup_for(viewer)
    GitHub.newsies.async_cleanup_inaccessible_thread_for_user(viewer.id, list_type, list_id, thread_type, thread_id)
  end

  memoize def newsies_list
    ::Newsies::List.new(list_type, list_id.to_i)
  end

  memoize def async_newsies_thread
    async_thread.then do |thread|
      Newsies::Thread.to_object(thread, list: newsies_list)
    end
  end

  def item_unread?(item)
    return false if item["user_id"] == @user.id
    return true if last_read_at.blank?
    last_read_at.to_i < item["created_at"].to_i
  end

  memoize def oldest_unread_item
    sorted_items.find { |item| item_unread?(item) }
  end

  memoize def summary_item
    oldest_unread_item || last_item
  end

  def last_item
    sorted_items.last
  end

  # Internal: Is the subject of the notification a pull request?
  #
  # Returns a Boolean.
  memoize def pull_request?
    async_pull_request?.sync
  end

  memoize def async_pull_request?
    async_info.then(&:async_pull_request?).then do |is_pull_request|
      next is_pull_request unless is_pull_request.nil?

      notification_entry[:is_pull_request]
    end
  end

  # Internal: Get an object that provides the minimal information for the current thread.
  # If the information provided is nil, fallback to the summarized entry information.
  #
  # Returns a Promise with an object that implements MinInfoTrait
  memoize def async_info
    return Promise.resolve(NullMinInfo.new) unless notification_entry[:reason] == "saved"

    case thread_type
    when "Issue"
      async_thread.then { |issue| IssueMinInfo.new(issue:) }
    when "Discussion"
      async_thread.then { |discussion| DiscussionMinInfo.new(discussion:) }
    when "Grit::Commit", "Commit"
      async_thread.then { |commit| CommitMinInfo.new(commit:) }
    when "Gist"
      async_thread.then { |gist| GistMinInfo.new(gist:) }
    when "Release"
      async_thread.then { |release| ReleaseMinInfo.new(release:) }
    when "RepositoryInvitation"
      async_thread.then { |repository_invitation| RepositoryInvitationMinInfo.new(repository_invitation:) }
    when "MemberFeatureRequest::Notification"
      async_thread.then { |request| MemberFeatureRequestMinInfo.new(request:) }
    when "AdvisoryCredit"
      async_thread.then { |advisory_credit| AdvisoryCreditMinInfo.new(advisory_credit:) }
    when "RepositoryAdvisory"
      async_thread.then { |repository_advisory| RepositoryAdvisoryMinInfo.new(user:, repository_advisory:) }
    when "SecurityAdvisory"
      Promise.all([async_list, async_thread]).then do |list, security_advisory|
        SecurityAdvisoryMinInfo.new(list:, security_advisory:)
      end
    when "RepositoryDependabotAlertsThread"
      Promise.all([async_list, async_thread]).then do |repository, dependabot_alert|
        RepositoryDependabotAlertsThreadMinInfo.new(repository:, dependabot_alert:)
      end
    when "RepositoryVulnerabilityAlert"
      async_thread.then { |alert| RepositoryVulnerabilityAlertMinInfo.new(alert:) }
    when "MemexProject"
      async_thread.then { |memex_project| MemexProjectMinInfo.new(memex_project:) }
    when "Actions::WorkflowRun"
      async_thread.then { |workflow_run| WorkflowRunMinInfo.new(workflow_run:) }
    when "CheckSuite"
      async_thread.then { |check_suite| CheckSuiteMinInfo.new(check_suite:) }
    else
      Promise.resolve(NullMinInfo.new)
    end
  end
end
