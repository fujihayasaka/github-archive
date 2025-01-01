# typed: true
# frozen_string_literal: true

# Notifications API!
#
# Note: The terminology for the external API is slightly different.  We're
# using "thread" to note a collection of messages.  The "subject" is the
# original message (such as the Issue or Commit).
#
# This terminology made more sense when writing the API documentation.
# Eventually the Newsies system will have to be refactored to go with this
# terminology.
class Api::Notifications < Api::App
  include ReceiveSchemaWithOpenApi

  ModifiedHeader = "HTTP_IF_MODIFIED_SINCE".freeze
  Scopes = %w(notifications repo).freeze
  DEFAULT_PER_PAGE = MAX_PER_PAGE = Newsies::NOTIFICATIONS_PER_PAGE

  before do
    @accepted_scopes = Scopes
  end

  def installation_required_for_read_access_to_public_resources?
    false
  end

  # Lists notifications for a user
  get "/notifications", operation_id: "activity/list-notifications-for-authenticated-user" do
    setup_response_for_uncredentialed_access
    control_access :notification_dashboard,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    repositories = if current_user.using_auth_via_granular_actor?
      repo_ids = Newsies::NotificationEntry.where(user_id: current_user.id, list_type: "Repository").distinct.pluck(:list_id)
      Repository.public_scope.where(id: repo_ids)
    else
      nil
    end

    GitHub.tracer.in_span("Api::Notifications#unauthorized_resource_ids", kind: :internal) do |span|
      unauthorized_sso_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations, only: :saml)
      span.set_attribute("unauthorized_sso_org_ids_count", unauthorized_sso_org_ids.count)
      set_sso_partial_results_header(unauthorized_sso_org_ids) if unauthorized_sso_org_ids.any?
    end

    filter = newsies_filter_for(repositories: repositories)
    deliver_summaries(filter, target_for_logging: repositories ? :via_github_apps : :all)
  end

  # Internal API used by GitHub Notifications
  get "/notifications/repositories", operation_id: :internal do
    @route_owner = "@github/notifications"
    setup_response_for_uncredentialed_access

    control_access :notification_dashboard,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    set_poll_interval_header!

    GitHub.tracer.in_span("Api::Notifications#unauthorized_resource_ids", kind: :internal) do |span|
      unauthorized_sso_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations, only: :saml)
      span.set_attribute("unauthorized_sso_org_ids_count", unauthorized_sso_org_ids.count)
      set_sso_partial_results_header(unauthorized_sso_org_ids) if unauthorized_sso_org_ids.any?
    end

    filter = newsies_filter_for

    GitHub.tracer.in_span("Api::Notifications#newsies_query_notifications", kind: :internal) do |_|
      start = Time.now
      response = GitHub.newsies.web.counts_by_list(current_user, filter)
      elapsed_ms = (Time.now - start) * 1_000

      variation = filter.list_type ? "with_list_type" : "without_list_type"
      result = response.success? ? :succeeded : :failed
      GitHub.dogstats.timing("api.notifications.count.#{variation}.#{result}", elapsed_ms)

      if response.failed?
        deliver_notifications_unavailable!
      end

      deliver :repository_unread_count, response.value
    end
  end

  # Gets a thread for a user.
  get "/notifications/threads/:thread_id", operation_id: "activity/get-thread" do
    summary = current_summary
    setup_response_for_uncredentialed_access

    record_or_404(summary&.thread)

    control_access :get_thread, resource: summary.thread, forbid: true, allow_integrations: false, allow_user_via_granular_actor: false

    set_poll_interval_header!

    response = GitHub.newsies.web.by_summaries(current_user, summary)
    if response.failed?
      deliver_notifications_unavailable!
    end

    notification_entry = response.first
    summary_hash = summary.to_summary_hash.update \
      unread: notification_entry.try(:unread?),
      reason: notification_entry.try(:reason)

    output = summaries_for_api([summary_hash])
    deliver_raw(output.first)
  end

  # update all notifications
  put "/notifications", operation_id: "activity/mark-notifications-as-read" do
    setup_response_for_uncredentialed_access
    control_access :notification_dashboard,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: false


    # Introducing strict validation of the notification-status.mark-all
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("notification-status", "mark-all", skip_validation: true)

    if data["unread"] || (data.key?("read") && !data["read"])
      deliver_empty status: 204
      return
    end

    time = Time.now
    if (str = data["last_read_at"]).present?
      time = parse_time!(str)
    end

    mark_as_read(time, current_user)

    deliver_empty status: 205
  end

  # mark a single summary as read
  verbs :patch, :post, "/notifications/threads/:thread_id", operation_id: "activity/mark-thread-as-read" do
    # Introducing strict validation of the notification-status.mark-thread
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("notification-status", "mark-thread", skip_validation: true)

    summary = current_summary

    if data["status"] == "read" || data["status"].nil?
      @documentation_url = "/rest/reference/activity#mark-a-thread-as-read"
      setup_response_for_uncredentialed_access
      control_access :mark_thread_as_read,
                     resource: current_repo,
                     enforce_oauth_app_policy: current_repo.private?,
                     forbid: true,
                     allow_integrations: false,
                     allow_user_via_granular_actor: false

      response = GitHub.newsies.web.mark_summary_read(current_user, summary)
    else
      deliver_error!(404)
    end

    if response.failed?
      deliver_notifications_unavailable!
    end

    deliver_empty status: 205
  end

  delete "/notifications/threads/:thread_id", operation_id: "activity/mark-thread-as-done" do
    # current_summary sets the current repo for control access so it needs to go before control_access
    summary = current_summary
    deliver_error!(404) unless summary

    @documentation_url = "/rest/reference/activity#mark-a-thread-as-done"

    setup_response_for_uncredentialed_access
    control_access :mark_thread_as_done,
                    resource: current_repo,
                    enforce_oauth_app_policy: current_repo.private?,
                    forbid: true,
                    allow_integrations: false,
                    allow_user_via_granular_actor: false

    receive_with_openapi

    response = GitHub.newsies.web.mark_summary_archived(current_user, summary)

    if response.failed?
      deliver_notifications_unavailable!
    end

    deliver_empty status: 204
  end

  # get notifications for a repository
  get "/repositories/:repository_id/notifications", operation_id: "activity/list-repo-notifications-for-authenticated-user" do
    control_access :list_repo_notifications, resource: current_repo, allow_integrations: false, allow_user_via_granular_actor: false

    filter = newsies_filter_for(repository: current_repo)
    deliver_summaries(filter, target_for_logging: :repository)
  end

  # update repository notifications
  put "/repositories/:repository_id/notifications", operation_id: "activity/mark-repo-notifications-as-read" do
    control_access :update_repo_notifications,
                   resource: current_repo,
                   enforce_oauth_app_policy: current_repo.private?,
                   allow_integrations: false,
                   allow_user_via_granular_actor: false

    # Introducing strict validation of the notification-status.mark-in-repo
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("notification-status", "mark-in-repo", skip_validation: true)

    if data["unread"] || (data.key?("read") && !data["read"])
      deliver_empty status: 204
      return
    end

    time = Time.now
    if (str = data["last_read_at"]).present?
      time = parse_time!(str)
    end
    mark_as_read(time, current_user, current_repo)

    deliver_empty status: 205
  end

  #TODO: redirect doesn't seem to carry preview flag or params or both?
  get "/notifications/threads", operation_id: :deprecated do
    @route_owner = "@github/notifications"
    control_access :apps_audited, resource: Platform::PublicResource.new, allow_integrations: false, allow_user_via_granular_actor: false # rubocop:disable GitHub/PublicResource

    deliver_redirect!(api_url("/notifications"), status: 301, documentation_url: "/v3/activity/notifications/#list-your-notifications")
  end

  # get the subscription for a thread
  get "/notifications/threads/:thread_id/subscription", operation_id: "activity/get-thread-subscription-for-authenticated-user" do
    summary = current_summary
    setup_response_for_uncredentialed_access

    thread = summary&.thread

    record_or_404(thread)

    control_access :get_thread_subscription,
                   resource: thread,
                   forbid: true,
                   allow_integrations: false,
                   allow_user_via_granular_actor: false

    response = Notifications::Subscriptions.subscription_status(current_user, summary.list, thread)

    if response.failed?
      deliver_notifications_unavailable!
    end

    subscription = response.value
    if subscription.valid?
      deliver :newsies_subscription_hash, subscription, summary: summary
    else
      deliver_error 404
    end
  end

  # subscribe to a thread
  put "/notifications/threads/:thread_id/subscription", operation_id: "activity/set-thread-subscription" do
    setup_response_for_uncredentialed_access

    summary = ActiveRecord::Base.connected_to(role: :reading) { current_summary }
    thread  = ActiveRecord::Base.connected_to(role: :reading) { summary&.thread }

    record_or_404(thread)

    control_access :subscribe_to_thread,
                   resource: thread,
                   enforce_oauth_app_policy: current_repo.private?,
                   forbid: true,
                   allow_integrations: false,
                   allow_user_via_granular_actor: false

    list = ActiveRecord::Base.connected_to(role: :reading) { summary.list }
    # Introducing strict validation of the notification-thread-subscription.update
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("notification-thread-subscription", "update", skip_validation: true)

    if data["ignored"] && data["subscribed"]
      deliver_error! 422, errors: [api_error(:Subscription, :subscribed, :invalid)]
    end

    if data["ignored"] && list && thread
      response = Notifications::Subscriptions.unsubscribe_from_thread(current_user, thread)
    elsif data["ignored"] && list
      response = GitHub.newsies.ignore_list(current_user, list)
    elsif thread
      response = Notifications::Subscriptions.subscribe_to_thread(current_user, list, thread, "manual")
    else
      response = GitHub.newsies.subscribe_to_list(current_user, list)
    end
    if response.failed?
      deliver_notifications_unavailable!
    end

    response = Notifications::Subscriptions.subscription_status(current_user, list, thread)
    if response.failed?
      deliver_notifications_unavailable!
    end

    deliver :newsies_subscription_hash, response.value, list: list, summary: summary
  end

  # delete a thread subscription
  delete "/notifications/threads/:thread_id/subscription", operation_id: "activity/delete-thread-subscription" do
    # Introducing strict validation of the notification-thread-subscription.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("notification-thread-subscription", "delete", skip_validation: true)

    summary = current_summary
    setup_response_for_uncredentialed_access
    control_access :unsubscribe_from_thread,
                   resource: current_repo,
                   enforce_oauth_app_policy: current_repo.private?,
                   forbid: true,
                   allow_integrations: false,
                   allow_user_via_granular_actor: false

    response = Notifications::Subscriptions.unsubscribe_from_thread(current_user, summary.thread)
    if response.failed?
      deliver_notifications_unavailable!
    end

    halt 204
  end

  # get the subscription for a repository
  get "/repositories/:repository_id/subscription", operation_id: "activity/get-repo-subscription" do
    control_access :get_repo_subscription, resource: current_repo, allow_integrations: false, allow_user_via_granular_actor: false

    response = GitHub.newsies.subscription_status(current_user, current_repo)
    if response.failed?
      deliver_notifications_unavailable!
    end

    subscription = response.value
    if subscription.valid?
      deliver :newsies_subscription_hash, subscription, list: current_repo
    else
      deliver_error 404
    end
  end

  # subscribe to a repository
  put "/repositories/:repository_id/subscription", operation_id: "activity/set-repo-subscription" do
    control_access :subscribe_to_repo,
                   resource: current_repo,
                   enforce_oauth_app_policy: current_repo.private?,
                   allow_integrations: false,
                   allow_user_via_granular_actor: false

    # Introducing strict validation of the repository-subscription.replace
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("repository-subscription", "replace", skip_validation: true)

    if data["ignored"] && data["subscribed"]
      deliver_error! 422, errors: [api_error(:Subscription, :subscribed, :invalid)]
    elsif data["ignored"]
      response = GitHub.newsies.ignore_list(current_user, current_repo)
    else
      response = GitHub.newsies.subscribe_to_list(current_user, current_repo)
    end
    if response.failed?
      deliver_notifications_unavailable!
    end

    response = GitHub.newsies.subscription_status(current_user, current_repo)
    if response.failed?
      deliver_notifications_unavailable!
    end

    deliver :newsies_subscription_hash, response.value, list: current_repo, summary: nil
  end

  # delete the subscription to a repository
  delete "/repositories/:repository_id/subscription", operation_id: "activity/delete-repo-subscription" do
    # Introducing strict validation of the repository-subscription.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("repository-subscription", "delete", skip_validation: true)

    control_access :unsubscribe_from_repo,
                   resource: current_repo,
                   enforce_oauth_app_policy: current_repo.private?,
                   allow_integrations: false,
                   allow_user_via_granular_actor: false

    response = GitHub.newsies.unsubscribe(current_user, current_repo)
    if response.failed?
      deliver_notifications_unavailable!
    end

    halt 204
  end

  private

  def mark_as_read(time, user, repository = nil)
    response = GitHub.newsies.web.mark_all_notifications_as_read(time, user, repository)

    deliver_notifications_unavailable! if response.failed?

    unless response.value
      message = "Unread notifications couldn't be marked in a single request. Notifications are being marked as read in the background."
      halt deliver_raw({ message: message }, status: 202)
    end
  end

  def current_summary
    return @current_summary if defined?(@current_summary)

    response = GitHub.newsies.web.find_rollup_summary_by_id(int_id_param!(key: :thread_id))
    if response.failed?
      @current_summary = nil
      deliver_notifications_unavailable!
    end

    @current_summary = response.value
    set_current_repo_for_access_control @current_summary.try(:list)

    @current_summary
  end

  def setup_response_for_uncredentialed_access
    challenge_api!

    if logged_in? && !current_user.oauth_access?(*@accepted_scopes)
      set_forbidden_message("Missing the 'notifications' scope.")
    end
  end

  def summaries_for_api(summaries)
    Api::Serializer.serialize(:rollup_summaries_hashes, summaries, map_items: false, current_user: current_user)
  end

  def deliver_summaries(filter, target_for_logging:)
    GitHub.tracer.in_span("Api::Notifications#deliver_summaries", kind: :internal) do |_|
      error_message = "Unable to parse If-Modified-Since request header. " \
                      "Please make sure value is in an acceptable format."
      caching_time = env[ModifiedHeader]
      caching_time = caching_time.present? ? parse_time!(caching_time, message: error_message) : nil
      filter.since = caching_time if caching_time
      filter.per_page = per_page

      set_poll_interval_header!

      GitHub.tracer.in_span("Api::Notifications#newsies_query_notifications", kind: :internal) do |_|
        start = Time.now
        response = GitHub.newsies.web.all(current_user, filter)
        elapsed_ms = (Time.now - start) * 1_000

        variation = filter.list_type ? :with_list_type : :without_list_type
        result = response.success? ? :succeeded : :failed
        GitHub.dogstats.timing("api.notifications.index.#{target_for_logging}.#{variation}.#{result}", elapsed_ms)

        if response.failed?
          deliver_notifications_unavailable!
        end

        summaries = response.value

        if summaries.any?
          set_caching_headers!(last_modified: summaries.first[:updated_at])
        end

        if summaries.none? && caching_time
          deliver_empty status: 304
        else
          # Fetch the total number of summaries for WillPaginate
          total_entries = GitHub.newsies.web.count(current_user, filter)

          collection = WillPaginate::Collection.new(pagination[:page], per_page, total_entries)
          formatted_summaries = summaries_for_api(summaries.take(per_page))
          paginated_summaries = collection.replace(formatted_summaries)

          deliver_raw paginated_summaries
        end
      end
    end
  end

  def newsies_filter_for(repository: nil, repositories: nil)
    GitHub.tracer.in_span("Api::Notifications#newsies_filter_for", kind: :internal) do |_|
      filter = Newsies::Web::FilterOptions.new

      if repositories
        filter.lists = repositories
      else
        filter.list_type = "Repository"
        filter.list = repository
      end

      filter.excluding = newsies_lists_to_exclude
      filter.page = [current_page, 1].max
      filter.unread = !parse_bool(params[:all])
      filter.participating = parse_bool(params[:participating])
      filter.since = time_param!(:since)
      filter.before = time_param!(:before)
      filter
    end
  end

  def poll_interval
    60
  end

  # Internal: Find the IDs of all repositories that the current user might have
  # notifications for, but that the current request is forbidden from accessing.
  #
  # Returns an Array of Fixnums.
  def newsies_lists_to_exclude
    GitHub.tracer.in_span("Api::Notifications#newsies_lists_to_exclude", kind: :internal) do |span|
      repository_ids = T.let([], T::Array[T.untyped])
      GitHub.tracer.in_span("Api::Notifications#newsies_lists_to_exclude", kind: :internal) do |span|
        unauthorized_account_ids = cap_filter.unauthorized_resource_ids(current_user&.resources_for_cap_filter)
        repository_ids += Organization.all_repo_ids_for_orgs_for_user(unauthorized_account_ids, current_user)
        span.set_attribute("unauthorized_account_ids", unauthorized_account_ids.count)
        span.set_attribute("unauthorized_accounts_repository_ids", repository_ids.count)
      end

      # Fetch the IDs of all private repositories where the OAuth app violates the
      # repository's OAuth application policy.
      if requestor_governed_by_oauth_application_policy?
        GitHub.tracer.in_span("Api::Notifications#newsies_lists_to_exclude_oauth_policy", kind: :internal) do |span|
          assosiated_repository_ids = T.let([], T::Array[T.untyped])
          GitHub.tracer.in_span("Api::Notifications#newsies_associated_repository_ids", kind: :internal) do |span|
            # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
            assosiated_repository_ids = current_user.associated_repository_ids(include_oauth_restriction: false)
            span.set_attribute("assosiated_repository_count", assosiated_repository_ids.count)
          end

          violated_repository_ids = Repository.oauth_app_policy_violated_repository_ids(
            repository_ids: assosiated_repository_ids,
            # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
            repository_scope: Repository.private_scope,
            app: current_app_via_oauth,
          )

          span.set_attribute("violated_repository_count", violated_repository_ids.count)
          repository_ids += violated_repository_ids
        end
      end
      span.set_attribute("repository_count", repository_ids.count)

      repository_ids.uniq.map { |id| Newsies::List.new("Repository", id) }
    end
  end
end
