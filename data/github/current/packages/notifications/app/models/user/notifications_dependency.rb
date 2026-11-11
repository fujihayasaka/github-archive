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

    unauthorized_resource_ids = unauthorized_resource_ids(cap_filter, direct_and_indirect_orgs: true)

    repos_by_id = if FeatureFlag.vexi.enabled?(:use_primary_not_owned_by_notifications_candidate, default: false)
      get_repos_for_counts(sorted_counts, unauthorized_resource_ids, true).index_by(&:id)
    else
      repos = science "use_primary_not_owned_by_notifications" do |e|
        e.use do
          get_repos_for_counts(sorted_counts, unauthorized_resource_ids, false)
        end
        e.try do
          get_repos_for_counts(sorted_counts, unauthorized_resource_ids, true)
        end
        # The result order is irrelevant here (it's immediately re-indexed by id),
        # and neither query specifies an explicit ORDER BY, so compare the ids
        # order-insensitively to avoid spurious experiment mismatches.
        e.compare_record_sequence
      end

      repos.index_by(&:id)
    end

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
    # The ids can be either a global id or a database id, the list may have a mix of both.
    label_ids.each do |global_or_database_id|
      to_create += build_label_subscriptions(repo, resolve_label_id(global_or_database_id))
    end

    request = Notifyd::Proto::Subscriptions::BatchReplaceRequest.new(
      user_id: id,
      new_subscriptions: to_create,
      replace_by_custom_fields: [
        Notifyd::Proto::Subscriptions::CustomField.new(name: "repository_id", value: repo.id.to_s),
        Notifyd::Proto::Subscriptions::CustomField.new(name: "label_id")
      ]
    )

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
    result = watch_repo_with_result(repo, enqueue: enqueue)
    return true if result == :ok
    # log if anything went wrong
    GitHub.logger.info("unable to fulfill watch request", {
      "code.namespace" => "User::NotificationsDependency",
      "code.method" => "watch_repo",
      "gh.notifications.watch_repo.failure_reason" => result
    })
    false
  end

  # Public: This is the same as #watch_repo but it returns the actual result of the operation
  # as a Symbol, with :ok as the success result and :failed, :forbidden and :limit_exceeded as
  # the failures. Clients can use this method to know exactly how the operation finished and why
  sig { params(repo: Repository, enqueue: T::Boolean).returns(Symbol) }
  def watch_repo_with_result(repo, enqueue: true)
    forbidden = !repo.pullable_by?(self) || repo.owner&.blocking?(self)
    return :forbidden if forbidden
    return :limit_exceeded if Notifications::Subscriptions.repository_subscription_limit_exceeded?(self)

    return :ok if Notifications::Subscriptions.repository_subscribed?(self, repo)
    return :ok if Notifications::Subscriptions.subscribe_to_repository(T.bind(self, User), repo)
    return :failed unless enqueue

    UserWatchRepoJob.perform_later(id, repo.id)
    :ok
  rescue ActiveRecord::RecordNotUnique
    :ok
  end

  def subscribe_to_thread_types(repo, thread_types)
    forbidden = !repo.pullable_by?(self) || repo.owner.blocking?(self)
    return false if forbidden

    Notifications::Subscriptions.subscribe_to_thread_types(T.bind(self, User), repo, thread_types)
  end

  # Unwatch a repository.
  def unwatch_repo(repo)
    Notifications::Subscriptions.unsubscribe_from_repository(T.bind(self, User), repo)
  end

  # Ignore a repository.
  def ignore_repo(repo)
    if repo.pullable_by?(self)
      Notifications::Subscriptions.mute_repository(T.bind(self, User), repo)
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
    Notifications::Subscriptions.repository_subscribed?(T.bind(self, User), repo) || false
  end

  def indicator_mode
    if self&.is_a?(User) && FeatureFlag.vexi.enabled?(:notifications_indicator_metrics, self, default: false)
      GitHub.dogstats.increment("notifications.indicator_checker.success", tags: ["action:indicator_mode"])
    else
      GitHub.dogstats.increment("notifications.indicator_checker.failed", tags: ["action:indicator_mode", "reason:user_not_found"])
    end
    indicator_checker.mode
  end

  # Lightweight check used by the global nav indicator preload: returns true
  # only when the user has web notifications disabled. Unlike `indicator_mode`,
  # this avoids the unread-notifications round-trip to newsies since the
  # indicator's unread/availability state is fetched asynchronously on the
  # client. Mirrors the `:disabled` semantics of `User::IndicatorChecker#mode`.
  #
  # Returns a Boolean.
  def web_notifications_disabled?
    !Notifications::Settings.web?(T.bind(self, User))
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

  # Retrieves the user's preferred notification sort order.
  #
  # Returns a persisted sort order string, or the notifications default when unset.
  def preferred_notifications_sort_order
    Notifications::KV.store.get(preferred_notifications_sort_order_key).value { nil }
      .presence_in(Notifications::SortOrder::OPTIONS.keys) || Notifications::SortOrder::DEFAULT
  end

  # Caches the user's preferred notification sort order.
  #
  # sort_order - The persisted sort direction.
  #
  # Returns nil.
  def set_preferred_notifications_sort_order(sort_order)
    Notifications::KV.store.set(preferred_notifications_sort_order_key, sort_order)
    nil
  end

  # Public - Disable all notifications for this user.
  sig { returns(T::Boolean) }
  def disable_all_notifications
    # This is only scarcely used (in the creation of ghost and staff users)
    # but its usage is scattered all over the place in both production
    # and specially testing code.
    return true if GitHub::AppEnvironment.test?
    T.bind(self, User)
    Notifications::Settings.disable_all(self)
  end

  def notify_web_notifications_changed_socket_subscribers(wait, indicator_mode: nil)
    channel = GitHub::WebSocket::Channels.notifications_changed(self)

    GitHub::WebSocket.notify_user_channel(id, channel,
      indicator_mode: indicator_mode || self.indicator_mode,
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
    @indicator_checker ||= User::IndicatorChecker.new(self)
  end

  def preferred_notifications_query_key
    "user.notifications_query.#{id}"
  end

  def notifications_group_by_list_key
    "user.notifications_group_by_list.#{id}"
  end

  def preferred_notifications_sort_order_key
    "user.notifications_sort_order.#{id}"
  end

  def resolve_label_id(global_or_database_id)
    id = global_or_database_id.to_s
    # assume the ID is a database ID if it's just digits
    return global_or_database_id if id.match?(/\A\d+\z/)

    _, decoded_id = Platform::Helpers::NodeIdentification.from_global_id(id)
    decoded_id
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

  def get_repos_for_counts(sorted_counts, unauthorized_resource_ids, use_primary_index)
    scope = Repository
      .includes(:owner)
      .not_owned_by(unauthorized_resource_ids)
      .where(id: sorted_counts.map { |(list, _, _)| list.id })

    if use_primary_index
      scope = scope.from("`#{Repository.table_name}` FORCE INDEX (PRIMARY)")
    end

    scope.to_a
  end
end
