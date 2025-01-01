# typed: true
# frozen_string_literal: true

require "notifyd-client"

module User::NotificationsDependency
  extend T::Helpers
  include ActiveSupport::Concern
  include Notifyd::NetworkHelper

  requires_ancestor { User }

  class RepoNotificationCountsResult
    attr_reader :repository, :total_count, :unread_count

    def initialize(repository:, total_count:, unread_count:)
      @repository = repository
      @total_count = total_count
      @unread_count = unread_count
    end
  end

  # Counts the number of outstanding notifications per repository for this user.
  #
  # cap_filter - ConditionalAccess::Web::Filter to use for enforcing authorization
  # statuses - Array<Symbol> where each symbol is one of :inbox_unread, :inbox_read, and :archived
  # limit - The maximum number of repositories to represent in the results.
  #
  # Returns nil if the operation failed, otherwise Array<RepoyNotificationCountResult> with entries for up to `limit`
  #   repositories with the most unread notifications.
  def repo_notification_counts(cap_filter:, statuses: [:inbox_unread, :inbox_read], limit: 25)
    unsorted_counts_response = GitHub.newsies.web.counts_by_list(
      self,
      {
        statuses: statuses,
        list_type: "Repository",
      }
    )
    return nil if unsorted_counts_response.failed?

    sorted_counts = unsorted_counts_response.value.sort_by { |_, _, unread_count| -unread_count }

    repos_by_id = Repository
      .includes(:owner)
      .not_owned_by(
        cap_filter.unauthorized_resource_ids(
          resources_for_cap_filter(direct_and_indirect_orgs: true)
        )
      )
      .where(id: sorted_counts.map { |(list, _, _)| list.id })
      .index_by(&:id)

    async_authorized_repo_ids = repos_by_id.values.map do |repo|
      repo.async_readable_by?(self).then { |readable| repo.id if readable }
    end
    authorized_repo_ids = Set.new(Promise.all(async_authorized_repo_ids).sync.compact)

    sorted_counts
      .select { |(list, _, _)| authorized_repo_ids.include?(list.id) }
      .take(limit)
      .map do |(list, total_count, unread_count)|
        RepoNotificationCountsResult.new(
          repository: repos_by_id[list.id],
          total_count: total_count,
          unread_count: unread_count
        )
      end
  end

  # Public: subscribes the user to receive notifications for issues that have given labels
  #
  # Returns a boolean
  def subscribe_to_labels(repo, label_ids)
    forbidden = !repo.pullable_by?(self) || repo.owner.blocking?(self)
    return false if forbidden
    return false if notifyd_client.nil?

    to_create = T.let([], T::Array[T.untyped])
    label_ids.each do |label_id|
      to_create += build_label_subscriptions(repo, label_id)
    end

    request = Notifyd::Proto::Subscriptions::BatchReplaceRequest.new({
      user_id: id,
      new_subscriptions: to_create,
      replace_by_custom_fields: [
        { name: "repository_id", value: repo.id.to_s },
        { name: "label_id" }
      ]
    })

    response = make_network_request_to_notifyd(request.class.name) do
      notifyd_client.subscriptions.batch_replace(request)
    end
    return false unless response

    true
  end

  # Public - update notification routing for an organization this user is affiliated with.
  #
  # organization - organization whose routing to update
  # new_email - new email address for notifications for this organization
  #
  # Returns: Boolean (or raises an Exception for failures along the way)
  def update_organization_notifications_routing(organization, new_email)
    unless affiliated_organizations.include?(organization)
      raise ArgumentError, "You can only configure email routing for organizations you are affiliated with."
    end

    email = new_email.strip.downcase
    if organization.restrict_notifications_to_verified_domains?
      org_notifiable_emails = organization.notifiable_emails_for(self).map { |email| email.email.downcase }
      error_message = "Couldn't save #{new_email} because it is not eligible to receive notifications for this organization."
      raise(ArgumentError, error_message) unless org_notifiable_emails.include?(email)
    end

    eligible_emails = notifiable_emails.map(&:downcase)
    unless eligible_emails.include?(email)
      # Clear unverified emails if somehow an unverified email is set to receive notifications
      response = GitHub.newsies.get_and_update_settings(self) do |settings|
        settings.clear_unverified_emails(eligible_emails)
      end

      if response.success?
        raise ArgumentError, "Couldn't save #{new_email} because it is not verified."
      else
        raise User::NotificationServiceError, "Unable to update notification settings."
      end
    end

    response = GitHub.newsies.get_and_update_settings(self) do |settings|
      settings.email organization, email
      settings.clear_unverified_emails(eligible_emails)
    end

    response.success?
  end

  # Subscribe to a team notifications
  def subscribe_team(team)
    return false unless Team.member_of?(team.id, id)

    GitHub.newsies.subscribe_to_list(self, team).success?
  end

  # Unsubscribe to a team notifications
  def unsubscribe_team(team)
    return false unless Team.member_of?(team.id, id)

    GitHub.newsies.unsubscribe(self, team).success?
  end

  # Ignore a team.
  def ignore_team(team)
    return false unless Team.member_of?(team.id, id)

    GitHub.newsies.ignore_list(self, team).success?
  end

  # API-Public
  #
  # Subscribes the user to a repository for being notified about updates to it.
  #
  # A User can't watch a repo either if they don't have read access to it
  # or if the owner is blocking them.
  #
  # In case the notifications cluster is not available we enqueue a job,
  # any call to a GitHub.newsies service will fail, and we enqueue a job
  # for retrying the operation later if we didn't succeed.
  #
  # Params:
  #  - repo, the repository to subscribe to
  #  - enqueue, defaults to true, indicates whether to enqueue a job in
  #    case of failure or not.
  #
  # Returns true if after calling this, the user eventually watches the repository, false
  # otherwise.
  #
  # This means that if the notifications cluster is down, we will enqueue a job
  # for repeating the operation later, and the user will eventually be watching the repo,
  # so it will return true.
  #
  def watch_repo(repo, enqueue: true)
    forbidden = !repo.pullable_by?(self) || repo.owner.blocking?(self)
    return false if forbidden

    status_response = GitHub.newsies.subscription_status(self, repo)
    return true if status_response.success? && status_response.subscribed?
    return true if GitHub.newsies.subscribe_to_list(self, repo).success?
    return false unless enqueue

    UserWatchRepoJob.perform_later(id, repo.id)
    true
  rescue ActiveRecord::RecordNotUnique
    true
  end

  def subscribe_to_thread_types(repo, thread_types)
    forbidden = !repo.pullable_by?(self) || repo.owner.blocking?(self)
    return false if forbidden

    response = GitHub.newsies.subscribe_to_thread_types(self, repo, thread_types)
    response.success?
  end

  # Unwatch a repository.
  def unwatch_repo(repo)
    GitHub.newsies.unsubscribe(self, repo).success?
  end

  # Ignore a repository.
  def ignore_repo(repo)
    if repo.pullable_by?(self)
      response = GitHub.newsies.ignore_list(self, repo)
      response.success?
    else
      unwatch_repo(repo)
    end
  end

  # Deprecated: Is this user watching a repository?. This method is not
  # resilient as it returns only true/false. This means that it will return
  # false if notifications are down even if the user is subscribed.
  #
  # repo - The Repository in quesiton.
  #
  # Returns a Boolean.
  def watching_repo?(repo)
    GitHub.newsies.subscription_status(self, repo).subscribed?
  end

  def indicator_mode
    indicator_checker.mode(self)
  end

  def wants_vulnerability_cli_notifications?
    settings_response = newsies_settings_response
    return false unless settings_response

    settings_response.success? && settings_response.vulnerability_cli?
  end

  def newsies_settings_response
    @newsies_settings_response ||= ActiveRecord::Base.connected_to(role: :reading) do
      GitHub.newsies.settings(self)
    end
  end

  # Retrieves the user's cached preference for the default query against their
  # notifications inbox at https://github.com/notifications/beta.
  #
  # Returns a String for the user's preferred query or nil if the user has none.
  def preferred_notifications_query
    Notifications::KV.store.get(preferred_notifications_query_key).value { nil }
  end

  # Caches the user's preferred query string for their notifications inbox at
  # https://github.com/notifications/beta.
  #
  # parsed_query - Search::Queries::NotificationsQuery
  #
  # Returns nil.
  def set_preferred_notifications_query(query_string)
    ActiveRecord::Base.connected_to(role: :writing) do
      if query_string.blank?
        Notifications::KV.store.del(preferred_notifications_query_key)
      else
        Notifications::KV.store.set(preferred_notifications_query_key, GitHub::KV::BINARY(query_string))
      end
    end

    nil
  end

  # Checks to see if the user prefers to view notification inbox grouped by list.
  #
  # Returns boolean.
  def prefer_notifications_grouped_by_list?
    Notifications::KV.store.exists(notifications_group_by_list_key).value!
  end

  # Sets that the user prefers to view their notification inbox grouped by list.
  #
  # Returns nil.
  def set_prefers_notifications_group_by_list_view
    Notifications::KV.store.set(notifications_group_by_list_key, "true")
  end

  # Unsets that the user prefers to view their notification inbox grouped by list.
  #
  # Returns nil.
  def unset_prefers_notifications_group_by_list_view
    Notifications::KV.store.del(notifications_group_by_list_key)
  end

  # Checks to see if the user has dismissed the suggestion to unwatch repositories
  #
  # Returns boolean.
  def dismissed_unwatch_suggestions?
    Notifications::KV.store.get(notifications_dismissed_unwatch_suggestions_key).value { false }
  end

  # Sets that the user dismissal of unwatch notifications suggestions
  #
  # Returns nil.
  def set_dismissed_unwatch_suggestions(expiry_time: 30.days.from_now)
    Notifications::KV.store.set(notifications_dismissed_unwatch_suggestions_key, "true", expires: expiry_time)
  end

  # Public - Disable all notifications for this user.
  #
  # Returns nil.
  def disable_all_notifications
    GitHub.newsies.get_and_update_settings self do |settings|
      T.bind(self, User)

      settings.participating_settings.clear
      settings.subscribed_settings.clear
      settings.vulnerability_cli = false
      settings.vulnerability_web = false
      settings.vulnerability_email = false
      settings.continuous_integration_web = false
      settings.continuous_integration_email = false

      Notifyd::RoutingSettingsService.update_handlers(user: self, settings: settings)
    end
  end

  def notify_web_notifications_changed_socket_subscribers(wait)
    channel = GitHub::WebSocket::Channels.notifications_changed(self)

    GitHub::WebSocket.notify_user_channel(id, channel,
      indicator_mode: indicator_mode,
      wait: wait,
    )
  end

  # Public: The user's notification email address
  #
  # Use this to get the default notification email for a user
  def default_notification_email
    if user? && is_enterprise_managed? && profile&.email
      return T.must(profile).email
    end

    email
  end

  private

  def indicator_checker
    @indicator_checker ||= User::IndicatorChecker.new
  end

  def preferred_notifications_query_key
    "user.notifications_query.#{id}"
  end

  def notifications_group_by_list_key
    "user.notifications_group_by_list.#{id}"
  end

  def notifications_dismissed_unwatch_suggestions_key
    "user.notifications_dismissed_unwatch_suggestions.#{id}"
  end

  def build_label_subscriptions(repo, label_id)
    [{
      reason: "subscribed",
      topics: [{ type: "repository", value: repo.id.to_s }],
      filters: [
        {
          subject_type: "Issue",
          trigger: "create",
          match_rules: [
            { attribute: "has_label", value: label_id.to_s, match_rule: "eq" },
          ]
        },
        {
          subject_type: "IssueComment",
          trigger: "create",
          match_rules: [
            { attribute: "has_label", value: label_id.to_s, match_rule: "eq" },
          ]
        },
      ],
      custom_fields: [
        { name: "repository_id", value: repo.id.to_s },
        { name: "label_id", value: label_id.to_s },
        { name: "label_name", value: repo.labels.find(label_id).name },
        { name: "owner_id", value: repo.owner.id.to_s },
        { name: "subject_type", value: "Issue" },
      ]
    },
    {
      reason: "subscribed",
      topics: [{ type: "repository", value: repo.id.to_s }],
      filters: [
        {
          subject_type: "Issue",
          trigger: "labeled",
          match_rules: [
            { attribute: "added_label", value: label_id.to_s, match_rule: "eq" },
          ]
        },
        {
          subject_type: "Issue",
          trigger: "unlabeled",
          match_rules: [
            { attribute: "removed_label", value: label_id.to_s, match_rule: "eq" },
          ]
        }
      ],
      custom_fields: [
        { name: "repository_id", value: repo.id.to_s },
        { name: "label_id", value: label_id.to_s },
        { name: "label_name", value: repo.labels.find(label_id).name },
        { name: "owner_id", value: repo.owner.id.to_s },
        { name: "subject_type", value: "Issue" },
      ]
    }]
  end

  def notifyd_client
    @notifyd_client ||= Notifyd.client
  end
end
