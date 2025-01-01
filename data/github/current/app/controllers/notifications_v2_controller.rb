# typed: true
# frozen_string_literal: true

class NotificationsV2Controller < ApplicationController
  layout "layouts/notifications_v2"

  # required to be able to make requests to this endpoint from react apps using the verifiedFetch function
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:toggle_inbox_feature]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    only: [:custom_inboxes_dialog]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:notifications_exist]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    only: [:shelf]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    only: [:notifications_restriction_banner]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Ballast,
    ApplicationRecord::Memex,
    only: [:recent_notifications_alert]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Repositories,
    only: [:filter_suggestions]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true


  INDEX_FEATURES = [
    :active_job_skip_enqueue,
    :verified_device_enforcement_opt_out,
    :ignorable_team_notifications,
    :encrypt_as_plaintext_user_weak_password_check_result,
    :otel_rack_middleware,
    :two_factor_checkup,
    :issues_react_inbox_tabs,
    :log_notifications_unauthorized_accounts,
    :notifications_exclude_entries_by_owner_id,
    :notifications_unified_sso_banner,
    :notifications_unified_sso_banner_alphabetical_order,
    :notifyd_enable_gist_thread_subscriptions,
    :notifyd_enable_issue_thread_subscriptions,
    :notifyd_issue_watch_activity_notify,
    :notifyd_primary_gist,
    :emu_vss_business,
    :api_insights_rest,
    :copilot_conversational_ux_license_check,
    :copilot_cb_rollout,
    :copilot_ce_rollout,
    :copilot_cs_rollout,
    :copilot_limited_rollout,
    :copilot_pro_plus_rollout,
    :copilot_pro_rollout,
    :munger_client_get_option_defaults,
    :copilot_natural_language_github_search,
    :private_avatars,
    :reserved_domain,
    :remove_shelf_limited_paths,
    :enterprise_teams_org_assignment,
    :notification_jobs_dual_read,
    :notification_jobs_write_to_target,
    :notification_jobs_dual_write,
    :disable_notifications_automatic_watching_repositories,
    :disable_notifications_automatic_watching_teams,
    :limit_execution_time_notification_entries,
    :limit_execution_time_indicator,
    :notifications_remove_force_index,
    :copilot_api_override_url_fallback,
  ].freeze

  preload_features INDEX_FEATURES, only: [:index]

  before_action :login_required
  before_action :redirect_to_preferred_inbox_view, only: [:index]
  before_action :require_selected_summaries_or_mark_all, only: [:mark_as_read, :mark_as_unread, :mark_as_archived]
  before_action :require_selected_summaries, only: [:mark_as_unarchived, :mark_as_subscribed, :mark_as_unsubscribed, :mark_as_starred, :mark_as_unstarred]
  before_action :require_this_custom_inbox, only: [:update_custom_inbox, :delete_custom_inbox]
  before_action :require_xhr, only: [:create_custom_inbox, :update_custom_inbox, :delete_custom_inbox, :custom_inboxes_dialog]

  check_for_sso [:index]

  # These controller actions skip the CAP checks because they all filter
  # through CAP the resources they load.
  #
  # For more information read: https://github.com/github/proxima/issues/3305#issuecomment-1954303090
  ACTIONS_SKIPPING_CAP_CHECKS = %i[
    index mark_as_read mark_as_unread mark_as_archived mark_as_unarchived
    mark_as_subscribed mark_as_unsubscribed mark_as_starred mark_as_unstarred
    recent_notifications_alert notifications_exist
  ]

  # These are write actions that only effect the resources privates to users
  # (their notifications) so they can be written without EMU control involved.
  #
  # For more information: https://github.com/github/notifications/issues/4142
  ACTIONS_SKIPPING_EMU_OWNERSHIP_CHECKS = %w[
    mark_as_read mark_as_unread mark_as_archived mark_as_unarchived
    mark_as_subscribed mark_as_unsubscribed
  ]

  skip_before_action :perform_conditional_access_checks, only: ACTIONS_SKIPPING_CAP_CHECKS # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  stylesheet_bundle :notifications

  REFERRER_PARAMS = [
    :notification_referrer_id,
    :notifications_after,
    :notifications_before,
    :notifications_query,
  ]

  PAGE_SIZE = 25
  RECENT_NOTIFICATIONS_MAX_COUNT = 10
  FILTER_SUGGESTION_SIZE = 100

  def index
    context_region_preset :notifications

    # Force page to be refreshed after pressing the back button
    headers["Cache-Control"] = "no-cache, no-store"

    filters = GitHub.newsies.web.all_custom_inboxes(current_user.id).value
    GitHub::PrefillAssociations.prefill_batch_method(filters, :unread_count)

    connection = notifications_connection
    notifications = preload_notifications_data(connection)

    track_time(tags: ["method:index", "step:render"]) do
      render(
        "notifications/v2/index",

        # Don't render any layout for XHR update requests
        layout: (request.xhr? && !pjax?) ? false : "layouts/notifications_v2",

        locals: {
          total_count: connection.total_count,
          first_item_offset: connection.first_item_offset,
          page_info: Platform::ConnectionWrappers::PageInfo.new(
            start_cursor: connection.start_cursor,
            end_cursor: connection.end_cursor,
            has_previous_page: connection.has_previous_page,
            has_next_page: connection.has_next_page,
          ),
          notifications: notifications,
          view: Notifications::V2::IndexView.new(
            index_view_params.merge(
              filters: filters,
              inbox_unread_count: notifications_connection(filter_by: { statuses: [:inbox_unread] }).total_count,
              repo_notification_counts: current_user.repo_notification_counts(
                cap_filter: cap_filter,
                limit: Notifications::V2::IndexView.repo_notification_counts_limit(current_user, parsed_query)
              ),
            )
          ),
          last_notification_timestamp: Time.now.utc
        }
      )
    end
  end

  def set_preferred_inbox_query # rubocop:todo GitHub/UseRestfulActions
    if parsed_query.is_only_an_inbox_query?
      current_user.set_preferred_notifications_query(parsed_query.query)
    end

    redirect_to notifications_path(query: parsed_query.query)
  end

  def update_view_preference # rubocop:todo GitHub/UseRestfulActions
    if params[:view_preference] == "group_by_repository"
      current_user.set_prefers_notifications_group_by_list_view
    elsif params[:view_preference] == "sort_by_date"
      current_user.unset_prefers_notifications_group_by_list_view
    end

    redirect_to notifications_path(query: parsed_query.query)
  end

  def mark_as_read # rubocop:todo GitHub/UseRestfulActions
    if params[:shelf_bar] == "true" && current_user.feature_flag_enabled_or_raise?(:notifications_shelf_bar_metrics) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      GitHub.dogstats.increment("notifications.shelf_bar.mark_as_read")
    end
    return mark_all(:read) if mark_all_request?

    unless GitHub.newsies.web.mark_summaries_as_read(current_user, selected_summary_ids).success?
      return head :service_unavailable
    end

    log_action_to_hydro(:read)
    head :ok
  rescue PlatformHelper::ConditionalAccessError
    head :unauthorized
  end

  def mark_as_unread # rubocop:todo GitHub/UseRestfulActions
    if params[:shelf_bar] == "true" && current_user.feature_flag_enabled_or_raise?(:notifications_shelf_bar_metrics) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      GitHub.dogstats.increment("notifications.shelf_bar.mark_as_unread")
    end
    return mark_all(:unread) if mark_all_request?

    unless GitHub.newsies.web.mark_summaries_as_unread(current_user, selected_summary_ids).success?
      return head :service_unavailable
    end

    log_action_to_hydro(:unread)
    head :ok
  rescue PlatformHelper::ConditionalAccessError
    head :unauthorized
  end

  def mark_as_archived # rubocop:todo GitHub/UseRestfulActions
    if params[:shelf_bar] == "true" && current_user.feature_flag_enabled_or_raise?(:notifications_shelf_bar_metrics) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      GitHub.dogstats.increment("notifications.shelf_bar.mark_as_archived")
    end
    return mark_all(:archived) if mark_all_request?

    unless GitHub.newsies.web.mark_summaries_as_archived(current_user, selected_summary_ids).success?
      return head :service_unavailable
    end

    log_action_to_hydro(:archive)
    head :ok
  rescue PlatformHelper::ConditionalAccessError
    head :unauthorized
  end

  def mark_as_unarchived # rubocop:todo GitHub/UseRestfulActions
    if params[:shelf_bar] == "true" && current_user.feature_flag_enabled_or_raise?(:notifications_shelf_bar_metrics) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      GitHub.dogstats.increment("notifications.shelf_bar.mark_as_unarchived")
    end
    unless GitHub.newsies.web.mark_summaries_as_read(current_user, selected_summary_ids).success?
      return head :service_unavailable
    end

    log_action_to_hydro(:unarchive)
    head :ok
  end

  def mark_as_subscribed # rubocop:todo GitHub/UseRestfulActions
    if params[:shelf_bar] == "true" && current_user.feature_flag_enabled_or_raise?(:notifications_shelf_bar_metrics) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      GitHub.dogstats.increment("notifications.shelf_bar.mark_as_subscribed")
    end
    selected_threads.each do |notification_thread, thread|
      next if thread.nil?
      # SecurityAdvisory does not implement newsies interface (notifications_thread method) so we fallback to old logic
      if thread.is_a?(SecurityAdvisory)
        newsies_thread = to_newsies_thread(notification_thread)
        unless GitHub.newsies.subscribe_to_thread(current_user, newsies_thread.list, newsies_thread, "manual").success?
          return head :service_unavailable
        end
      else
        unless Notifications::Subscriptions.subscribe_to_thread(current_user, thread.notifications_list, thread, "manual").success?
          return head :service_unavailable
        end
      end
    end

    unless GitHub.newsies.web.mark_summaries_as_read(current_user, selected_summary_ids).success?
      return head :service_unavailable
    end

    head :ok
  end

  def mark_as_unsubscribed # rubocop:todo GitHub/UseRestfulActions
    if params[:shelf_bar] == "true" && current_user.feature_flag_enabled_or_raise?(:notifications_shelf_bar_metrics) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      GitHub.dogstats.increment("notifications.shelf_bar.mark_as_unsubscribed")
    end
    selected_threads.each do |notification_thread, thread|
      next if thread.nil?

      # SecurityAdvisory does not implement newsies interface (notifications_thread method) so we fallback to old logic
      # MemberFeatureRequest::Notification opts out directly from Notifyd
      if thread.is_a?(SecurityAdvisory)
        newsies_thread = to_newsies_thread(notification_thread)
        Newsies::ThreadSubscriptionManager.unsubscribe_from_thread(current_user, newsies_thread.list, newsies_thread)
      elsif thread.is_a?(MemberFeatureRequest::Notification)
        member_feature_request_unsubscription[thread.entity_id] << MemberFeatureRequest::Feature.from_string(thread.feature)
      else
        Notifications::Subscriptions.unsubscribe_from_thread(current_user, thread)
      end
    end

    if member_feature_request_unsubscription.any?
      MemberFeatureRequest::Notification.unsubscribe(
        user: current_user,
        unsubscription: member_feature_request_unsubscription
      )
    end

    unless GitHub.newsies.web.mark_summaries_as_archived(current_user, selected_summary_ids).success?
      return head :service_unavailable
    end

    log_action_to_hydro(:unsubscribe)
    head :ok
  end

  def mark_as_starred # rubocop:todo GitHub/UseRestfulActions
    if params[:shelf_bar] == "true" && current_user.feature_flag_enabled_or_raise?(:notifications_shelf_bar_metrics) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      GitHub.dogstats.increment("notifications.shelf_bar.mark_as_starred")
    end
    selected_notification_threads.each do |notification_thread|
      next if notification_thread.is_starred

      newsies_thread = to_newsies_thread(notification_thread)
      unless GitHub.newsies.web.save_thread(current_user, newsies_thread).success?
        return head :service_unavailable
      end
    end

    log_action_to_hydro(:star)
    head :ok
  end

  def mark_as_unstarred # rubocop:todo GitHub/UseRestfulActions
    if params[:shelf_bar] == "true" && current_user.feature_flag_enabled_or_raise?(:notifications_shelf_bar_metrics) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      GitHub.dogstats.increment("notifications.shelf_bar.mark_as_unstarred")
    end
    selected_notification_threads.each do |notification_thread|
      next unless notification_thread.is_starred

      newsies_thread = to_newsies_thread(notification_thread)
      unless GitHub.newsies.web.unsave_thread(current_user, newsies_thread).success?
        return head :service_unavailable
      end
    end

    log_action_to_hydro(:unstar)
    head :ok
  end

  def recent_notifications_alert # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless params[:since]

    begin
      threads = notification_threads(limit: RECENT_NOTIFICATIONS_MAX_COUNT + 1)
    rescue Platform::Errors::Execution
      return head :service_unavailable
    end

    since = Time.at(params[:since].to_i)
    unread_count = threads.count { |thread| thread.last_updated_at > since }

    render partial: "notifications/v2/recent_notifications_alert", locals: {
      unread_count: unread_count,
      since: since,
      max_count: RECENT_NOTIFICATIONS_MAX_COUNT,
      view: Notifications::V2::IndexView.new(index_view_params),
    }
  end

  # Checks if any notifications exist for the current query
  def notifications_exist # rubocop:todo GitHub/UseRestfulActions
    begin
      has_threads = notification_threads(limit: 1).first.present?
    rescue Platform::Errors::Execution
      return head :service_unavailable
    end

    respond_to do |format|
      format.json do
        render json: { notifications_exist: has_threads }
      end
    end
  end

  def custom_inboxes_dialog # rubocop:todo GitHub/UseRestfulActions
    filters = GitHub.newsies.web.all_custom_inboxes(current_user.id).value

    render partial: "notifications/v2/custom_inboxes_dialog_contents", locals: { notification_filters: filters }
  end

  def create_custom_inbox # rubocop:todo GitHub/UseRestfulActions
    input = custom_inbox_params

    response = GitHub.newsies.web.create_custom_inbox(user_id: current_user.id, name: input["name"], query_string: input["query_string"])

    return head :service_unavailable if response.failed?
    return head :bad_request unless response.value.persisted?

    head :created
  end

  def update_custom_inbox # rubocop:todo GitHub/UseRestfulActions
    input = custom_inbox_params
    response = GitHub.newsies.web.update_custom_inbox(
      id: this_custom_inbox.id,
      name: input["name"],
      query_string: input["query_string"]
    )

    updated_inbox = response.value
    return head :not_found if response.failed? || updated_inbox.nil?
    return head :bad_request unless updated_inbox.valid?

    head :ok
  end

  def delete_custom_inbox # rubocop:todo GitHub/UseRestfulActions
    response = GitHub.newsies.web.destroy_custom_inbox(this_custom_inbox.id)

    return head :not_found if response.failed?

    destroyed_inbox = response.value
    return head :not_found unless destroyed_inbox.destroyed?

    head :ok
  end

  def filter_suggestions # rubocop:todo GitHub/UseRestfulActions
    filter = params[:filter]

    result = case filter
    when "repositories"
      suggested_repositories
    when "authors"
      suggested_authors
    when "owners"
      suggested_owners
    end

    respond_to do |format|
      format.json do
        render json: result
      end
    end
  end

  def suggested_repositories # rubocop:todo GitHub/UseRestfulActions
    counts = current_user.repo_notification_counts(
      cap_filter: cap_filter,
      statuses: [:inbox_unread, :inbox_read, :archived],
      limit: FILTER_SUGGESTION_SIZE,
    )
    return head :service_unavailable if counts.nil?
    counts.map { |c| { value: c.repository.name_with_display_owner } }
  end

  def suggested_owners # rubocop:todo GitHub/UseRestfulActions
    distinct_owner_ids = user_suggestions_time(["action:owners"]) do
      Newsies::NotificationEntry
        .for_user(current_user)
        .select("DISTINCT owner_id, MAX(updated_at) as max_updated_at")
        .group(:owner_id)
        .order("max_updated_at DESC")
        .limit(FILTER_SUGGESTION_SIZE)
        .map(&:owner_id)
        .compact
    end

    User.where(id: distinct_owner_ids).
      sort_by { |user| distinct_owner_ids.index(user.id) }.
      map { |user| { value: user.display_login } }
  end

  def suggested_authors # rubocop:todo GitHub/UseRestfulActions
    unauth_orgs_ids = unauthorized_account_ids
    unauth_orgs_ids = [-1] if unauth_orgs_ids.empty? # add an invalid ID because IN clause will not work properly with an empty list
    distinct_author_ids = user_suggestions_time(["action:authors"]) do
      Newsies::NotificationEntry.where("owner_id not IN(?)", unauth_orgs_ids)
        .for_user(current_user)
        .select("DISTINCT author_id, MAX(updated_at) as max_updated_at")
        .group(:author_id)
        .order("max_updated_at DESC")
        .limit(FILTER_SUGGESTION_SIZE)
        .map(&:author_id)
        .compact
    end

    User.where(id: distinct_author_ids).
      sort_by { |user| distinct_author_ids.index(user.id) }.
      map { |user| { value: user.display_login } }
  end

  def shelf # rubocop:todo GitHub/UseRestfulActions
    render Notifications::TopShelfComponent.new(referrer: notification_referrer), layout: false
  end

  def notifications_restriction_banner # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless FeatureFlag.vexi.enabled?(:notifications_async_verified_domain_banner, current_user, default: true)
    return head :not_found unless current_organization

    render VerifiableDomains::NotificationBannerComponent.new(
      organization: current_organization,
      deferred: false
    ), layout: false
  end

  private

  memoize def current_organization
    if params[:org]
      Organization.find_by_login(params[:org])
    end
  end

  memoize def member_feature_request_unsubscription
    Hash.new { |h, k| h[k] = [] }
  end

  def custom_inbox_params
    params.require(:custom_inbox).permit(:id, :name, :query_string)
  end

  def mark_all_request?
    params[:mark_all] == "1"
  end

  def mark_all(state)
    # query parameter must be set to something, even if it's empty string
    return head(:bad_request) if params[:query].nil?
    return head(:forbidden) if parsed_query.contains_unsupported_qualifiers?

    mark_at = Time.now.utc

    filter_options = {}
    filter_options[:before] = mark_at
    filter_options[:thread_types] = filter_by_thread_types
    filter_options[:lists] = filter_by_list_ids
    filter_options[:owners] = filter_by_owner_ids
    filter_options[:authors] = filter_by_author_ids

    filter_options[:reasons] = if filter_by_reasons
      parsed_query.reasons.map(&:to_sym)
    end

    filter_options[:statuses] = if filter_by_statuses.empty?
      # If a user is in the `All` view, we want everything that is not archived
      [:unread, :read]
    else
      # Otherwise, use whatever statuses they have in their query
      parsed_query.statuses.map(&:to_sym)
    end

    filter_options.compact!

    # We only allow the user to run one mark_all_from_query job at a time.
    # If there is an existing job running, return with 409 and let the user know.
    status = Newsies::MarkAllNotificationsFromQueryJobStatus.status(current_user.id)
    return head :conflict if status && !status.finished?

    unless GitHub.newsies.web.mark_all_from_query(current_user, state, filter_options).success?
      return head :service_unavailable
    end

    # Given we are processing this request in a background job, we use the accepted status code here
    # instead of success. The consumer can then use the JobStatus generated by the job to check when it's complete.
    # i.e. Newsies::MarkAllNotificationsFromQueryJobStatus.status(current_user.id)
    #
    # We use this on the client to decide if we need to display the "processing" toast to the user.
    head :accepted
  end

  def log_action_to_hydro(action)
    summary_response = GitHub.newsies.web.find_rollup_summaries_by_ids(selected_summary_ids)

    if summary_response.success?
      summary_response.value.each do |summary|
        GlobalInstrumenter.instrument(
          "notifications.#{action}",
          {
            list_type: summary.newsies_list.type,
            list_id: summary.newsies_list.id,
            thread_type: summary.newsies_thread.type,
            thread_id: summary.newsies_thread.id,
            comment_type: summary.last_comment.type,
            comment_id: summary.last_comment.id,
            handler: :web,
            user: current_user,
            version: :v2,
          },
        )
      end
    end
  end

  def require_selected_summaries_or_mark_all
    # We don't need the selected summaries for marking all from a query,
    # but we do want them for individual and bulk actions
    head :not_found unless selected_summary_ids.present? || mark_all_request?
  rescue PlatformHelper::ConditionalAccessError
    # this is an xhr request, so follow the pattern in
    # https://github.com/github/github/blob/4bf41fdfcdc9b7b30615e5dc7df6ae55bf73c583/app/controllers/application_controller/external_sessions_dependency.rb#L186-L187
    # we have to do this manually now because Rails will throw a
    # DoubleRenderError if we try to call `head :unauthorized` after
    # setting the response body
    # https://github.com/github/github/pull/371615#issuecomment-2797250608
    response.reset_body!
    response.status = :unauthorized
  end

  def require_selected_summaries
    head :not_found unless selected_summary_ids.present?
  rescue PlatformHelper::ConditionalAccessError
    # this is an xhr request, so follow the pattern in
    # https://github.com/github/github/blob/4bf41fdfcdc9b7b30615e5dc7df6ae55bf73c583/app/controllers/application_controller/external_sessions_dependency.rb#L186-L187
    head :unauthorized
  end

  def redirect_to_preferred_inbox_view
    # don't redirect XHR only requests
    return if request.xhr? && !pjax?

    # don't redirect if a query is present, even if empty
    return unless params[:query].nil?

    if (preference = current_user.preferred_notifications_query).present?
      redirect_to notifications_path(query: preference)
    end
  end

  def index_view_params
    {
      before: params[:before].presence,
      after: params[:after].presence,
      query: parsed_query,
      user: current_user,
    }
  end

  # cap_bypass:to_fix - why is it okay to skip CAP in all actions for this controller?
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  memoize def parsed_query
    Search::Queries::NotificationsQuery.new(query: params[:query], viewer: current_user)
  end

  def graphql_filter_variables
    { query: params[:query] || "" }
  end

  def filter_by_reasons
    parsed_query.qualifier_used?(:reason) ? parsed_query.reasons.map(&:upcase) : nil
  end

  def filter_by_list_ids
    parsed_query.qualifier_used?(:repo) ? parsed_query.repositories.map(&:global_relay_id) : nil
  end

  def filter_by_owner_ids
    parsed_query.qualifier_used?(:org) ? parsed_query.owners.map(&:global_relay_id) : nil
  end

  def filter_by_author_ids
    parsed_query.qualifier_used?(:author) ? parsed_query.authors.map(&:global_relay_id) : nil
  end

  def filter_by_thread_types
    parsed_query.thread_type? ? parsed_query.thread_types : nil
  end

  def filter_by_statuses
    parsed_query.statuses.map(&:upcase).presence
  end

  # Retrieve selected notification threads for markAs* methods
  #
  # We set { enforce_conditional_access_via_graphql: true } which means the
  # platform_execute call will errors that inherit from
  # PlatformHelper::ConditionalAccessError if any of the listed notifications
  # are in orgs where the user does not meet conditional access requirements.
  memoize def selected_notification_threads
    Platform::Security::RepositoryAccess.with_viewer(current_user) do
      Promise.all(selected_notification_ids.map do |id|
        async_selected_thread(id)
      end).sync.compact # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end

  # Retrieve selected threads for mark_as_(un)subscribed methods
  #
  # We set { enforce_conditional_access_via_graphql: true } which means the
  # platform_execute call will errors that inherit from
  # PlatformHelper::ConditionalAccessError if any of the listed notifications
  # are in orgs where the user does not meet conditional access requirements.
  memoize def selected_threads
    Platform::Security::RepositoryAccess.with_viewer(current_user) do
      Promise.all(selected_notification_ids.map do |id|
        async_selected_thread(id).then do |selected_thread|
          selected_thread&.async_thread.then do |thread|
            [selected_thread, thread]
          end
        end
      end).sync.compact # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end

  memoize def selected_summary_ids
    selected_notification_threads.map(&:summary_id)
  end

  def to_newsies_thread(notification_thread)
    list = Newsies::List.new(notification_thread.list_type, notification_thread.list_id)
    Newsies::Thread.new(notification_thread.thread_type, notification_thread.thread_id, list: list, subscription_type: notification_thread.subscription_type)
  end

  memoize def this_custom_inbox
    typed_object_from_id([Platform::Objects::NotificationFilter], custom_inbox_params["id"])
  rescue Platform::Errors::NotFound, Platform::Errors::ServiceUnavailable
    nil
  end

  def require_this_custom_inbox
    head :not_found unless this_custom_inbox
  end

  def user_suggestions_time(tags = [])
    timer = Timer.start
    result = yield(timer)
    timer.stop

    GitHub.dogstats.distribution("newsies.distinct_user_suggestions.time", timer.elapsed_ms, tags: tags)

    result
  end

  memoize def unauthorized_account_ids
    cap_filter.unauthorized_resource_ids(
      current_user.resources_for_cap_filter(
        direct_and_indirect_orgs: true
      )
    )
  end

  def selected_notification_ids
    Array(params[:notification_ids]).first(PAGE_SIZE).filter_map do |id|
      parsed = Platform::Helpers::GlobalId.parse(id)
      parsed if parsed.type == "NotificationThread"
    rescue Platform::Errors::NotFound
      nil
    end
  end

  def async_selected_thread(id)
    loader = if id.is_a?(Platform::Helpers::GlobalId::Next)
      Platform::Objects::NotificationThread.load_from_next_global_id(id)
    else
      Platform::Objects::NotificationThread.load_from_global_id(id.id)
    end

    loader.then do |thread|
      next unless thread.present?
      async_selected_thread_readable?(thread).then { |readable| thread if readable }
    end
  end

  def async_selected_thread_readable?(thread)
    promises = [
      thread.async_target_for_conditional_access,
      thread.async_in_unauthorized_account?(unauthorized_account_ids),
      thread.async_readable_by?(current_user),
    ]

    Promise.all(promises).then do |tfca, unauthorized, readable|
      if tfca.present? && cap_enforcer.enforce_conditional_access_policies(tfca) != :ok
        raise PlatformHelper::ConditionalAccessError
      end

      raise PlatformHelper::ConditionalAccessError if unauthorized

      readable
    end
  end

  # This is a callback used by ConditionalAccess::Web::Enforcer. With it we
  # ensure that EMU users can act on their notifications
  private def emu_ownership_enforceable
    return :no if ACTIONS_SKIPPING_EMU_OWNERSHIP_CHECKS.include?(action_name)
    :yes
  end

  private def notifications_connection(filter_by: nil, limit: PAGE_SIZE)
    pagination_params = valid_graphql_pagination_params(page_size: limit)
    flash[:error] = "Sorry, we couldn't find that page" unless pagination_params.valid?

    Platform::ConnectionWrappers::Notifications.new(
      Platform::Helpers::NotificationThreadsQuery.new(
        {
          filter_by: filter_by,
          query: filter_by ? nil : params.fetch(:query, ""),
          unauthorized_account_ids: unauthorized_account_ids,
          internal_request: true,
        }.compact,
        current_user
      ),
      **pagination_params.to_h
    )
  end

  private def notification_threads(**kwargs)
    Platform::Security::RepositoryAccess.with_viewer(current_user) do
      notifications_connection(**kwargs).edge_nodes
    end
  end

  private def preload_notifications_data(connection)
    Platform::Security::RepositoryAccess.with_viewer(current_user) do
      notifications = connection.edge_nodes

      Promise.all(
        notifications.map do |notification|
          notification.async_list.then do |list|
            notification.async_subject.then do |subject|
              Promise.all(
                [
                  notification.async_subscription_status,
                  notification.async_url,
                  notification.async_recent_participants,
                  list.is_a?(Repository) ? list.async_organization : nil,
                  subject.is_a?(CheckSuite) ? subject.async_workflow_run : nil,
                  subject.is_a?(Actions::WorkflowRun) ? subject.async_workflow : nil,
                ].compact
              )
            end
          end
        end
      ).sync

      notifications
    end
  end
end
