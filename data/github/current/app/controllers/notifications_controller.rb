# typed: true
# frozen_string_literal: true

class NotificationsController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:update_settings, :subscribe]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    only: [:thread_subscription_dialog]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    only: [:watch_subscription]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    only: [:beacon]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:email_mute_via_list]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:email_mute_via_footer]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Collab,
    only: [:email_mute_vulnerabilities]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Spokes,
    only: [:subscription]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:watching]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    only: [:unsubscribe_via_email]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:thread_subscription]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:watching, :subscription, :thread_subscription, :unsubscribe_via_email,
      :email_mute_via_list],
    optional: true

  SUBSCRIPTIONS_PER_PAGE = 25
  UNWATCH_ALL_LIMIT = 10

  # The only events we currently support subscribing to with custom thread notifications
  SUPPORTED_THREAD_SUBSCRIPTION_EVENTS = %w(
    closed
    reopened
    merged
  )

  SUPPORTED_SUBSCRIPTION_THREAD_TYPES = %w(
    Discussion
    Issue
    PullRequest
    Release
    SecurityAlert
  )

  UNWATCH_LIMIT = 10

  # These limits exist to add bounds to the repository owners queries to
  # prevent slow queries or excessive page bloat.
  # - 99% of users are subscribed to 99 or fewer repositories
  # - 99.9% are subscribed to 476 or fewer repositories
  # - 99% are subscribed to repos with 12 or fewer distinct owners
  # - 99.9% are subscribed to repos with 55 or fewer distinct owners
  # xref https://github.com/github/special-projects/issues/472#issuecomment-987740181
  #
  # Allow unsubscribing from specific repository owners when a user is watching
  # 10,000 or fewer repositories. The owner lookup in this case should take
  # around 175ms.
  # xref https://github.com/github/special-projects/issues/472#issuecomment-979936522
  MAX_REPOS_FOR_OWNERS_LOOKUP = 10_000
  # Limit the number of repository owners shown in the dropdown to the p99.9 to
  # avoid rendering an unbounded number of elements.
  MAX_REPO_OWNERS_SHOWN = 55

  around_action :select_write_database, only: [:unsubscribe_via_email, :email_mute_via_list, :email_mute_via_footer, :email_mute_vulnerabilities]

  before_action :start_timer, only: :index
  after_action :send_timer, only: :index

  before_action :login_required, except: [:beacon, :email_mute_via_list]
  before_action :summary_required, only: [:mark_as_unread]
  before_action :validate_thread_subscription_events, only: [:thread_subscribe]
  before_action :validate_thread_types_set_when_using_custom_settings, only: [:subscribe]

  check_for_sso [:watching]

  # This must come *after* login_required, so we don't check the repository's
  # privacy settings before we check if the user is logged in.
  include RepositoryControllerMethods
  include ActionView::Helpers::NumberHelper

  def index
  end

  def mark_as_read # rubocop:todo GitHub/UseRestfulActions
    response = \
      if params[:ids].present?
        GitHub.newsies.web.mark_summaries_as_read(current_user, params[:ids])
      else
        response = GitHub.newsies.web.mark_all_notifications_as_read(notification_mark_time, current_user, current_list)
        if response.success? && !response.value
          flash[:notice] = "We are marking your notifications as read right now. This may take a minute or two to process."
        end

        response
      end

    flash[:error] = "Mark as read is not available at the moment." if response.failed?

    if request&.xhr?
      head response.success? ? 200 : 503
    else
      redirect_to notifications_path
    end
  end

  def mark_as_unread # rubocop:todo GitHub/UseRestfulActions
    response = GitHub.newsies.web.mark_summary_unread(current_user, summary)
    head(response.success? ? 200 : 503)
  end

  # A page to manage your subscription status for a specific repository
  def subscription # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_list.is_a?(Repository)
    return render_404 if current_list.hide_from_user?(current_user)

    @subscription_response = GitHub.newsies.subscription_status(current_user, current_list)
    @subscription = @subscription_response.value

    render "notifications/subscription"
  end

  # Unsubscribe from the current repo. Intended to be hit via email.
  def unsubscribe_via_email # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_list.is_a?(Repository)

    if GitHub.newsies.valid_unsubscribe_token? params[:data], current_user, current_list
      response = GitHub.newsies.unsubscribe current_user, current_list
      if response.success?
        flash[:notice] = "You are no longer watching this repository."
      else
        flash[:error] = "Unsubscribe is not available at the moment."
      end
    else
      flash[:error] = "Sorry, someone sent you an invalid link."
    end

    redirect_to repository_path(current_list)
  end

  GIF = "GIF89a\001\000\001\000\200\377\000\377\377\377\000\000\000,\000\000\000\000\001\000\001\000\000\002\002D\001\000;".b

  def beacon # rubocop:todo GitHub/UseRestfulActions
    begin
      user, id, extra_data = GitHub.newsies.user_and_id_from_token :beacon, params[:data]
      if user && id
        summary_response = GitHub.newsies.web.find_rollup_summary_by_id(id)
        summary = summary_response.value
        if summary_response.success? && summary.present?
          summary_hash_response = GitHub.newsies.web.summary_hash_from_summary_id(user, id)
          summary_hash = summary_hash_response.value
          # Only mark unread items as read
          if summary_hash_response.success? && summary_hash.present? && summary_hash[:unread]
            last_operations = ::DatabaseSelector::LastOperations.from_session(session)
            ::DatabaseSelector.instance.track_writes(last_operations) do
              ActiveRecord::Base.connected_to(role: :writing) do
                GitHub.newsies.web.mark_summary_read(user, summary)
              end
            end
          end

          if extra_data.present?
            GlobalInstrumenter.instrument(
              "notifications.read",
              user: user,
              list_type: summary.newsies_list.type,
              list_id: summary.newsies_list.id,
              thread_type: summary.newsies_thread.type,
              thread_id: summary.newsies_thread.id,
              comment_type: extra_data["comment_type"],
              comment_id: extra_data["comment_id"],
              handler: :email,
            )
          end
        end
      end
    rescue Exception => e # rubocop:todo Lint/RescueException
      NotificationsFailbot.report!(e)
    end
    send_data GIF, type: "image/gif", disposition: "inline"
  end

  def email_mute_via_footer # rubocop:todo GitHub/UseRestfulActions
    unsubscribe_from_link = UnsubscribeFromLink.new(:mute_auth, params[:data])
    auth, resource = unsubscribe_from_link.auth, unsubscribe_from_link.resource

    unless auth.valid?
      return render_email_mute_view(auth.result, auth.result)
    end

    unless resource.valid?
      return redirect_to(
        GitHub.url,
        flash: { error: "Whoops! Cannot find the thread you want to unsubscribe from." }
      )
    end

    Failbot.push("gh.user.id": auth.user&.id)
    if !auth.for_user?(current_user)
      return redirect_to(
        GitHub.url,
        flash: { error:  "Whoops! That unsubscribe link isn't valid for your account." }
      )
    end

    result = unsubscribe_from_link.unsubscribe

    unless resource.readable_by?(current_user)
      return redirect_to(
        GitHub.url,
        flash: { error: "Whoops! That unsubscribe link isn't valid for your account." }
      )
    end

    return render_email_mute_view(auth.result, result) unless logged_in?

    redirect_to resource.permalink, notice: "You’ve been unsubscribed from this thread."
  end

  def email_mute_via_list # rubocop:todo GitHub/UseRestfulActions
    unsubscribe_from_link = UnsubscribeFromLink.new(:mute_list, params[:data])
    auth, resource = unsubscribe_from_link.auth, unsubscribe_from_link.resource
    return render_email_mute_view(auth.result, nil) unless auth.valid?

    unless resource.valid?
      return redirect_to(
        GitHub.url,
        flash: { error: "Whoops! Cannot find the thread you want to unsubscribe from." }
      )
    end

    Failbot.push("gh.user.id": auth.user&.id)
    result = unsubscribe_from_link.unsubscribe

    if current_user && !resource.readable_by?(current_user)
      return redirect_to(
        GitHub.url,
        flash: { error: "Whoops! That unsubscribe link isn't valid for your account." }
      )
    end

    return render_email_mute_view(auth.result, result) unless logged_in?

    redirect_to resource.permalink, notice: "You’ve been unsubscribed from this thread."
  end

  def email_mute_vulnerabilities # rubocop:todo GitHub/UseRestfulActions
    user, _ = GitHub.newsies.user_and_id_from_token(:mute_vuln, params[:data])

    if user
      Failbot.push("gh.user.id": user.id)
      if current_user&.display_login != user.display_login
        flash[:error] = "Whoops! That unsubscribe link isn't valid for your account."
      else
        unless Notifications::Settings.disable_vulnerability_email(user)
          flash[:error] = "Updating notification settings is unavailable right now."
        end
      end
    end

    flash[:notice] = "You will no longer receive email notifications when a new vulnerability is found in one of your dependencies."
    redirect_to settings_notification_preferences_path
  end

  def subscribe # rubocop:todo GitHub/UseRestfulActions
    xhr_error_status = 404
    is_success = false

    if params[:repository_global_id]
      repo = typed_object_from_id([Platform::Objects::Repository], params[:repository_global_id])
    else
      repo = if FeatureFlag.vexi.enabled?(:repos_domain_controllers, default: false)
        Repositories.domain.by_id(params[:repository_id].to_i)
      else
        Repository.find_by(id: params[:repository_id].to_i)
      end
    end

    if repo && repo.pullable_by?(current_user)
      xhr_error_status = request&.get? ? 405 : 422

      is_success =
        case params[:do]
        when "release_only" then current_user&.subscribe_to_thread_types(repo, [Release])
        when "custom"       then label_subscriptions_enabled?(repo, current_user) ? custom_subscribe(repo) : current_user&.subscribe_to_thread_types(repo, valid_thread_type_subscriptions)
        when "subscribed"   then current_user&.watch_repo(repo)
        when "ignore"       then current_user&.ignore_repo(repo)
        else                     current_user&.unwatch_repo(repo)
        end

      # If the user wants to move from a label subscription to say being "subscribed" then we need to remove
      # the label subscriptions from notifyd otherwise we will have conflicting records in different DB's.
      # We only want to do this if the do parameter is not "custom",if the do parameter is "custom",
      # we will have handled labels in that custom logic.
      unsubscribe_from_labels(repo) if label_subscriptions_enabled?(repo, current_user) && is_success && params[:do] != "custom"
    end

    if request&.xhr?
      if is_success
        render json: { count: number_with_delimiter(repo.watchers_count) }
      else
        head(xhr_error_status)
      end
    else
      flash[:notice] = "Subscription status updated." if is_success
      location = request&.referrer.present? ? :back : watching_path
      redirect_to location
    end
  end

  def update_subscription_status # rubocop:todo GitHub/UseRestfulActions
    is_success = false

    if params[:repository_global_id]
      repo = typed_object_from_id([Platform::Objects::Repository], params[:repository_global_id])
    else
      repo = if FeatureFlag.vexi.enabled?(:repos_domain_controllers, default: false)
        Repositories.domain.by_id(params[:repository_id].to_i)
      else
        Repository.find_by(id: params[:repository_id].to_i)
      end
    end

    if repo && repo.pullable_by?(current_user)
      is_success =
        case params[:do]
        when "release_only" then current_user&.subscribe_to_thread_types(repo, [Release])
        when "custom"       then label_subscriptions_enabled?(repo, current_user) ? custom_subscribe(repo) : current_user&.subscribe_to_thread_types(repo, valid_thread_type_subscriptions)
        when "subscribed"   then current_user&.watch_repo(repo)
        when "ignore"       then current_user&.ignore_repo(repo)
        else                     current_user&.unwatch_repo(repo)
        end

      # If the user wants to move from a label subscription to say being "subscribed" then we need to remove
      # the label subscriptions from notifyd otherwise we will have conflicting records in different DB's.
      # We only want to do this if the do parameter is not "custom",if the do parameter is "custom",
      # we will have handled labels in that custom logic.
      unsubscribe_from_labels(repo) if label_subscriptions_enabled?(repo, current_user) && is_success && params[:do] != "custom"
    end

    if is_success
      respond_to do |format|
        format.html do
          render(
            Repositories::NotificationsComponent.new(
              aria_id_prefix: "repo-#{repo.id}",
              repository: repo,
              status: GitHub.newsies.subscription_status(current_user, repo),
              show_count: params[:show_button_counter] == "true",
              deferred_content: false,
              # after a response, ensure that the watch button receives focus
              auto_focus: true
            ),
            layout: false,
          )
        end
      end
    else
      head(422)
    end
  end

  def custom_subscribe(repo) # rubocop:todo GitHub/UseRestfulActions
    subscribe_to_labels = params[:labels].present? && params[:thread_types]&.include?("Issue")

    if subscribe_to_labels
      params[:thread_types].delete("Issue")
      # First we subscribe to thread_types or cleanup the thread type subscriptions if user unchecked them
      current_user&.subscribe_to_thread_types(repo, valid_thread_type_subscriptions)

      resp = measure_time("notifyd.subscribe_to_labels") do
        current_user&.subscribe_to_labels(repo, params[:labels])
      end

      # just log the error and proceed with the rest of logic if we can't save the label subscriptions to new schema
      unless resp
        GitHub.logger.info("Saving new subscriptions failed", {
          "code.namespace" => "NotificationsController",
          "code.function" => "custom_subscribe",
          "gh.notifications.request_params" => params
        })
        return false
      end

      GitHub.dogstats.increment("newsies.subscribe_to_labels.sync_mismatch.count") unless params[:thread_types]&.filter_map(&:presence).present?
      true
    else
      unsubscribe_from_labels(repo)
      current_user&.subscribe_to_thread_types(repo, valid_thread_type_subscriptions)
    end
  end

  def unwatch_all # rubocop:todo GitHub/UseRestfulActions
    if params[:owner_id]
      owner = User.find(params[:owner_id])
      GitHub.newsies.async_delete_all_for_user_and_repository_owner(current_user&.id, owner.id, params[:subscription_type])
    else
      GitHub.newsies.async_delete_for_user_and_all_repositories(current_user&.id, "Repository", params[:subscription_type])
    end

    flash[:notice] = (
      "We're unwatching your repositories in the background. " +
      "This could take a while, so please check back later to see your changes."
    )

    redirect_to watching_path
  end

  class UnexpectedThreadTypeError < StandardError
    def initialize(thread_type, expected)
      @thread_type = thread_type
      @expected = expected
    end

    def message
      "#{@thread_type.inspect} isn’t one of #{@expected.inspect}"
    end
  end

  # Subscribe, unsubscribe, or mute a single thread.
  # This happens on the thread's page, eg issues/show
  #
  # params[:repository_id] - The repo you're acting on.
  #     params[:thread_id] - The thread (issue,commit) you're acting on.
  #  params[:thread_class] - The thread's class - Issue, Commit, Discussion.
  #            params[:id] - The String action to perform.
  #                          One of: subscribe, unsubscribe, mute, subscribe_to_custom_notifications.
  def thread_subscribe # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_list.is_a?(Repository)

    thread = GitHub.newsies.thread(
      current_list,
      params[:thread_class],
      params[:thread_id],
      actor: current_user)

    if !thread ||
      (thread.is_a?(Discussion) && !current_repository&.discussions_active?) ||
      !thread.readable_by?(current_user)

      head :not_found
      return
    end

    case thread_subscribe_action
    when "subscribe"
      Notifications::Subscriptions.subscribe_to_thread(current_user, current_list, thread, "manual")
    when "unsubscribe", "mute"
      # Newsies will do the correct thing internally based on the user's current
      # list subscription status.
      Notifications::Subscriptions.unsubscribe_from_thread(current_user, thread)
    when "subscribe_to_custom_notifications"
      Notifications::Subscriptions.subscribe_to_thread(
        current_user,
        current_list,
        thread,
        { reason: "manual", force: true },
        valid_thread_subscription_events(thread)
      )
    end

    respond_to do |format|
      format.html do
        if request&.xhr?
          render(
            Notifications::ThreadSubscriptionComponent.new(
              list: current_list,
              thread: thread,
              display_explanation_text: true,
            ),
            layout: false,
          )
        else
          path = case params[:thread_class]
          when "Issue"
            issue_path(thread)
          when "Commit"
            commit_path(thread)
          when "Discussion"
            discussion_path(thread)
          else
            error = UnexpectedThreadTypeError.new(params[:thread_class], %w[Issue Commit])
            error.set_backtrace(caller)
            NotificationsFailbot.report(error, "gh.notifications.thread.type": params[:thread_class])
            nil
          end

          redirect_to("#{path}#thread-subscription-status")
        end
      end
    end
  end

  def thread_subscription # rubocop:todo GitHub/UseRestfulActions
    thread = nil
    repo = if FeatureFlag.vexi.enabled?(:repos_domain_controllers, default: false)
      T.cast(Repositories.domain.by_id(params[:repository_id].to_i), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    else
      Repository.find_by(id: params[:repository_id].to_i)
    end
    if repo
      if repo.pullable_by?(current_user)
        thread = GitHub.newsies.thread(repo, params[:thread_class],
          params[:thread_id], actor: current_user)
      end
    end

    if !thread
      head :not_found
      return
    end

    render(
      Notifications::ThreadSubscriptionComponent.new(
        list: repo,
        thread: thread,
        display_explanation_text: true,
      ),
      layout: false,
    )
  end

  def watching # rubocop:todo GitHub/UseRestfulActions
    set_nav_breadcrumb ContextRegion::Notifications::WatchingCrumb.new

    current_user = T.must_because(self.current_user) { "#login_required ensures non-nil" }
    watching = Newsies::ListSubscription.subscriptions(
                current_user.id,
                list_type: Newsies::List.type_from_class(Repository),
                set: :subscribed,
                page: subscriptions_page,
                per_page: SUBSCRIPTIONS_PER_PAGE
              )
    authorized_watching, unauthorized_watching = watching.partition { |sub| sub.readable_by?(current_user) }

    watching_count = Newsies::ListSubscription.count_subscriptions(
                      current_user.id,
                      list_type: Newsies::List.type_from_class(Repository),
                      set: :subscribed
                    )

    custom = Newsies::ThreadTypeSubscription.subscriptions(
                current_user.id,
                list_type: Newsies::List.type_from_class(Repository),
                page: subscriptions_page,
                per_page: SUBSCRIPTIONS_PER_PAGE,
              )
    authorized_custom, unauthorized_custom = custom.partition { |sub| sub.readable_by?(current_user) }

    custom_count = Newsies::ThreadTypeSubscription.count_subscriptions(
                    current_user.id,
                    list_type: Newsies::List.type_from_class(Repository),
                  )

    ignoring = Newsies::ListSubscription.subscriptions(
                current_user.id,
                list_type: Newsies::List.type_from_class(Repository),
                set: :ignored,
                page: subscriptions_page,
                per_page: SUBSCRIPTIONS_PER_PAGE
              )
    authorized_ignoring, unauthorized_ignoring = ignoring.partition { |sub| sub.readable_by?(current_user) }

    ignoring_count = Newsies::ListSubscription.count_subscriptions(
                      current_user.id,
                      list_type: Newsies::List.type_from_class(Repository),
                      set: :ignored
                    )

    # Cleanup any inaccessible lists
    unauthorized_lists = [*unauthorized_watching, *unauthorized_custom, *unauthorized_ignoring].map do |sub|
      Notifications::Subject.new(type: "Repository", id: sub.list.id)
    end
    if unauthorized_lists.any?
      Notifications::Subscriptions.async_delete_user_subscriptions_for_lists(user_id: T.must(current_user.id), lists: unauthorized_lists)
    end

    authorized_repos = [*authorized_watching, *authorized_custom, *authorized_ignoring].map(&:list_object).compact
    GitHub::PrefillAssociations.prefill_associations(authorized_repos, [:owner, :organization])
    Configurable.preload_configuration(authorized_repos)

    all_subscriptions = [*authorized_watching, *authorized_custom, *authorized_ignoring]
    authorized_watching = cap_filter.authorized_resources(authorized_watching)
    authorized_custom = cap_filter.authorized_resources(authorized_custom)
    authorized_ignoring = cap_filter.authorized_resources(authorized_ignoring)
    cap_unauthorized_subscriptions = all_subscriptions - [*authorized_watching, *authorized_custom, *authorized_ignoring]

    render "notifications/watching", locals: {
      watching: authorized_watching,
      watching_count: watching_count,
      custom: authorized_custom,
      custom_count: custom_count,
      ignoring: authorized_ignoring,
      ignoring_count: ignoring_count
    }
  end

  def repo_owners # rubocop:todo GitHub/UseRestfulActions
    current_user = T.must_because(self.current_user) { "#login_required ensures non-nil" }
    if params[:subscription_type] == "custom"
      repo_count = Newsies::ThreadTypeSubscription.count_subscriptions(
                      current_user.id,
                      list_type: Newsies::List.type_from_class(Repository),
                    )

      repo_ids =  Newsies::ThreadTypeSubscription.subscriptions_list_ids(
                  current_user.id,
                  list_type: Newsies::List.type_from_class(Repository),
                  page: subscriptions_page,
                )
    elsif params[:subscription_type] == "ignoring"
      repo_count = Newsies::ListSubscription.count_subscriptions(
                        current_user.id,
                        list_type: Newsies::List.type_from_class(Repository),
                        set: :ignored
                      )

      repo_ids = Newsies::ListSubscription.subscriptions_list_ids(
                  current_user.id,
                  list_type: Newsies::List.type_from_class(Repository),
                  set: :ignored,
                  page: subscriptions_page,
                )
    else
      repo_count = Newsies::ListSubscription.count_subscriptions(
        current_user.id,
        list_type: Newsies::List.type_from_class(Repository),
        set: :subscribed
      )

      repo_ids = Newsies::ListSubscription.subscriptions_list_ids(
        current_user.id,
        list_type: Newsies::List.type_from_class(Repository),
        set: :subscribed,
      )
    end

    owner_id_counts = T.cast(
      Repository.where(id: repo_ids).group(:owner_id).limit(MAX_REPO_OWNERS_SHOWN).order(count_all: :desc).count,
      T::Hash[Integer, Integer]
    )
    repo_owners_with_counts = User.where(id: owner_id_counts.keys).reduce({}) do |h, owner|
      h.merge(owner => owner_id_counts[T.must(owner.id)])
    end

    render partial: "notifications/repo_owners", locals: {
      repo_owners_with_counts: repo_owners_with_counts,
      subscription_type: params[:subscription_type],
    }
  end

  def unwatch_repositories # rubocop:todo GitHub/UseRestfulActions
    unless params[:repository_ids].present?
      return redirect_to watching_path
    end

    lists = params[:repository_ids][0...UNWATCH_LIMIT].map { |id| Newsies::List.new(Newsies::List.type_from_class(Repository), id.to_i) }
    Notifications::Subscriptions.unwatch_repositories(current_user, lists)

    flash[:notice] = "Successfully unwatched suggested repositories."
    redirect_to watching_path
  end

  # Saves the preferred email for notifications
  def save_email_settings # rubocop:todo GitHub/UseRestfulActions
    current_user = T.must_because(self.current_user) { "#login_required ensures non-nil" }
    notifiable_emails = current_user.notifiable_emails
    redirect_path = settings_notification_preferences_path

    if params[:redirect_path] == "email_settings"
      redirect_path = settings_email_preferences_path
    end

    settings_response = GitHub.newsies.get_and_update_settings(current_user) do |settings|
      settings.email :global, params[:email].to_s.strip
      @cleared_emails = settings.clear_unverified_emails(notifiable_emails)
      @settings = settings
    end

    if settings_response.failed?
      flash[:error] = "Updating notification settings is unavailable right now."
      return redirect_to redirect_path
    end

    if @cleared_emails && GitHub.email_verification_enabled?
      flash[:error] = "The following emails are unverified: #{@cleared_emails.to_a.to_sentence}"
      redirect_to redirect_path
    else
      flash[:notice] = "Your default notification email was changed to #{@settings.email(:global).address}."
      redirect_to redirect_path
    end
  end

  def thread_subscription_dialog # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request&.xhr?

    repo = if FeatureFlag.vexi.enabled?(:repos_domain_controllers, default: false)
      Repositories.domain.by_id(params[:repository_id].to_i)
    else
      Repository.find_by(id: params[:repository_id].to_i)
    end
    thread = GitHub.newsies.thread(
      repo,
      params[:thread_class],
      params[:thread_id],
      actor: current_user)

    return head :not_found unless thread&.readable_by?(current_user)

    render(
      Notifications::ConfigureThreadSubscriptionDialogContentComponent.new(
        list: repo,
        thread: thread,
      ),
      layout: false,
    )
  end

  def watch_subscription # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless FeatureFlag.vexi.enabled?(:notifications_async_watch_repo_button, current_user, default: true)
    return head :not_found unless current_repository

    subscription_status = GitHub.newsies.subscription_status(current_user, current_repository)

    render(
      Repositories::NotificationsComponent.new(
        aria_id_prefix: params[:aria_id_prefix],
        repository: current_repository,
        show_count: params[:show_count] == "true" ? true : false,
        button_block: params[:button_block] == "true" ? true : false,
        status: subscription_status,
        deferred_content: false
      ),
      layout: false,
    )
  end

  def update_settings # rubocop:todo GitHub/UseRestfulActions
    return update_email_settings if params[:email]
    return update_auto_subscribe if params[:auto_subscribe_repositories] || params[:auto_subscribe_teams]

    return update_participating if params.keys.include?("participating_settings")
    return update_subscribed if params.keys.include?("subscribed_settings")
    return update_org_deploy_key if params.keys.include?("org_deploy_key_settings")
    return update_security_campaign_emails_subscription if params.keys.include?("subscribe_to_security_campaign_emails")

    if %w(web email failures_only).any? { |key| params.keys.include?("continuous_integration_#{key}") }
      return update_ci
    end

    if %w(ui_alert cli web email).any? { |key| params.keys.include?("vulnerability_#{key}") }
      return update_vulnerability
    end
    return update_vulnerability_digest if params[:vulnerability_digest]

    if %w(notify_pull_request_review_email notify_pull_request_push_email notify_comment_email notify_own_via_email).any? { |key| params.keys.include?(key) }
      return update_email_delivery_preferences
    end

    if params[:subscribe_to_in_product_messages]
      return update_in_product_messaging_subscription
    end

    head 400 # if params are missing we return bad_request
  end

  def update_email_settings # rubocop:todo GitHub/UseRestfulActions
    notifiable_emails = current_user&.notifiable_emails
    settings_response = GitHub.newsies.get_and_update_settings(current_user) do |settings|
      settings.email :global, params[:email].to_s.strip
      @cleared_emails = settings.clear_unverified_emails(notifiable_emails)
    end

    if @cleared_emails && GitHub.email_verification_enabled?
      error = "The following emails are unverified: #{@cleared_emails.to_a.to_sentence}"
      return handle_response(settings_response.success?, error)
    end

    handle_response(settings_response.success?)
  end

  def update_auto_subscribe # rubocop:todo GitHub/UseRestfulActions
    return head :not_found if FeatureFlag.vexi.enabled?(:disable_notifications_automatic_watching, current_user, default: true)

    settings_response = GitHub.newsies.get_and_update_settings(current_user) do |settings|
      settings.auto_subscribe_repositories = params[:auto_subscribe_repositories] == "1" if params.key?(:auto_subscribe_repositories)
      settings.auto_subscribe_teams = params[:auto_subscribe_teams] == "1" if params.key?(:auto_subscribe_teams)
    end

    handle_response(settings_response.success?)
  end

  def update_ci # rubocop:todo GitHub/UseRestfulActions
    response = Notifications::Settings.set_actions(
      current_user,
      Notifications::Settings::ActionsSettings.new(
        email: params[:continuous_integration_email] == "1",
        web: params[:continuous_integration_web] == "1",
        failures: params[:continuous_integration_failures_only] == "1",
      ),
    )

    handle_response(response)
  end

  def update_vulnerability # rubocop:todo GitHub/UseRestfulActions
    settings_response = GitHub.newsies.get_and_update_settings(current_user) do |settings|
      settings.vulnerability_cli = params[:vulnerability_cli] == "1" if params.key?(:vulnerability_cli)
    end

    handle_response(settings_response.success?) unless settings_response.success?

    response = Notifications::Settings.set_vulnerability(
      current_user,
      Notifications::Settings::VulnerabilitySettings.new(
        email: params[:vulnerability_email] == "1",
        web: params[:vulnerability_web] == "1",
      )
    )

    handle_response(response)
  end

  def update_email_delivery_preferences # rubocop:todo GitHub/UseRestfulActions
    response = Notifications::Settings.set_custom_email(
      current_user,
      issue_comment: params[:notify_comment_email] == "1",
      pull_request_review: params[:notify_pull_request_review_email] == "1",
      pull_request_push: params[:notify_pull_request_push_email] == "1",
      own: params[:notify_own_via_email] == "1",
    )

    handle_response(response)
  end

  def update_vulnerability_digest # rubocop:todo GitHub/UseRestfulActions
    begin
      current_user = T.must_because(self.current_user) { "#login_required ensures non-nil" }
      if params[:vulnerability_digest] == "1"
        if params[:subscription_kind] == "daily"
          NewsletterSubscription.subscribe(current_user, "vulnerability", "daily")
        else
          NewsletterSubscription.subscribe(current_user, "vulnerability", "weekly")
        end
      else
        @newsletter ||= NewsletterSubscription.where("user_id = ? AND name = ?", current_user.id, "vulnerability").first
        NewsletterSubscription.unsubscribe(@newsletter.unsubscribe_token) if @newsletter
      end
    rescue ActiveRecord::RecordInvalid => e
      return render json: { error: e.message }, status: 422
    end
    if request&.xhr?
      head 200
    else
      redirect_to settings_notification_preferences_path
    end
  end

  def update_in_product_messaging_subscription # rubocop:todo GitHub/UseRestfulActions
    subscription = current_user.in_product_messaging_subscription ||
                  current_user.create_in_product_messaging_subscription

    response = subscription.update(subscribed: params[:subscribe_to_in_product_messages] == "1")
    handle_response(response)
  end

  private

  def update_security_campaign_emails_subscription
    response = Notifications::Settings.set_security_campaigns(
      current_user,
      Notifications::Settings::SecurityCampaignsSettings.new(
        email: params[:subscribe_to_security_campaign_emails] == "1",
      )
    )

    handle_response(response)
  end

  def update_participating
    email = T.let(false, T::Boolean)
    web = T.let(false, T::Boolean)
    save_handler_params("participating_settings", [:web, :email]).each do |handler, checked|
      email = checked == "1" if handler == "email"
      web = checked == "1" if handler == "web"
    end
    response = Notifications::Settings.set_participant(
      T.must_because(self.current_user) { "#login_required ensures non-nil" },
      Notifications::Settings::ParticipantSettings.new(email: email, web: web),
    )
    handle_response(response)
  end

  def update_subscribed
    email = T.let(false, T::Boolean)
    web = T.let(false, T::Boolean)
    save_handler_params("subscribed_settings", [:web, :email]).each do |handler, checked|
      email = checked == "1" if handler == "email"
      web = checked == "1" if handler == "web"
    end

    response = Notifications::Settings.set_watcher(
      T.must_because(self.current_user) { "#login_required ensures non-nil" },
      Notifications::Settings::WatcherSettings.new(email: email, web: web),
    )
    handle_response(response)
  end

  def update_org_deploy_key
    current_user = T.must_because(self.current_user) { "#login_required ensures non-nil" }
    settings_response = GitHub.newsies.get_and_update_settings(current_user) do |settings|
      handlers = settings.org_deploy_key_settings
      save_handler_params("org_deploy_key_settings", [:email]).each do |handler, checked|
        if checked == "1"
          handlers << handler
        else
          handlers.delete(handler)
        end
      end
      handlers.uniq!
    end

    handle_response(settings_response.success?)
  end

  # The following actions do not need the EMU ownership policy.
  # We expect logged in users to be able to switch to an emu account
  def emu_ownership_enforceable
    return :no if %w(thread_subscribe).include?(action_name) && current_repository&.public
    :yes
  end

  # TODO: old unsubscribe page; consider redesigning or removing
  def render_email_mute_view(summary_response, mute_response)
    @view = Notifications::EmailMuteView.new(summary_response, mute_response)
    render "notifications/email_mute"
  end

  def handle_response(success, error = nil)
    if request&.xhr?
      return head 503 unless success
      return head 200 unless error

      render json: { error: error }, status: 422
    else
      unless success
        flash[:error] = "Updating notification settings is unavailable right now."
      end
      redirect_to settings_notification_preferences_path
    end
  end

  def unsubscribe_from_labels(repo)
    current_user&.subscribe_to_labels(repo, [])
  end

  def subscribed_labels_map
    subscribed_labels = current_repository.subscribed_labels(current_user)
    if subscribed_labels.nil? || subscribed_labels.length == 0
      subscribed_labels = {}
    else
      map = {}
      subscribed_labels.each do |label|
        map[label.id] = label
      end
      subscribed_labels = map
    end

    subscribed_labels
  end

  def target_for_conditional_access
    return current_repository.owner if current_repository.present?
    super
  end

  def resource_for_conditional_access
    return self unless current_repository
    current_repository
  end

  def save_handler_params(required_key, permitted_keys)
    return ActionController::Parameters.new unless params.key?(required_key)
    params.require(required_key).permit *permitted_keys
  end

  def start_timer
    @stats_timer = Time.now
  end

  def send_timer
    return unless @view

    ms = (T.unsafe(Time.now - @stats_timer) * 1000).round
    GitHub.dogstats.timing("newsies.view.new_inbox", ms)
    GitHub.dogstats.count("newsies.view.new_inbox.entries", @view.notifications.size)
  end

  def measure_time(metric)
    timer = Timer.start
    result = yield
    timer.stop
    GitHub.dogstats.distribution(metric, timer.elapsed_ms)
    result
  end

  # Overrides RepositoryControllerMethods#privacy_check.
  # This method is run as a `before_action` on every route.
  def privacy_check
    # Return early from a variety of cases if the privacy check passes.
    if current_list.is_a?(Team)
      return if current_list.visible_to?(current_user) && can_access_to_repo?
    elsif current_list.is_a?(Repository)
      return if current_list.pullable_by?(current_user)
    else
      return unless repository_specified?
    end

    if logged_in? && current_list.is_a?(Repository)
      CleanupListNotificationsJob.perform_later(current_user&.id, "Repository", [current_list.id])
      GitHub.dogstats.count("newsies.cleanup.inaccessible_lists", 1, tags: ["method:privacy_check"])
    end

    # Privacy check has failed, so respond with an error.
    request&.xhr? ? head(404) : render_404
  end

  def can_access_to_repo?
    return true unless FeatureFlag.vexi.enabled?(:notifications_bounty_repo_endpoint_permission, default: true)
    return true if current_repository.nil?

    current_repository.pullable_by?(current_user)
  end

  memoize def notification_mark_time
    Time.at(params[:mark_by].to_i)
  end

  helper_method :subscriptions_page
  memoize def subscriptions_page
    [params[:page].to_i, 1].max
  end

  def map_subscriptions_to_repositories(subscriptions, bad_list_set)
    repositories = []
    subscriptions.each do |sub|
      if sub.list
        repositories << sub.list
      else
        bad_list_set << sub.list_id
      end
    end
    repositories
  end

  # Private: Returns the current notification list as an object.
  def current_list
    if params[:list_type]&.downcase == "team"
      current_team
    elsif repository_specified?
      current_repository
    elsif params[:id]
      summary&.list
    end
  end

  memoize def current_team
    # HACK: Rather than commit to a large refactor of this controller, just repurpose the
    # repository argument for the team slug.
    team_slug = params[:repository]

    owner.teams.where(slug: team_slug).first if owner.is_a?(Organization) && team_slug.present?
  end

  def summary_required
    if !params[:id] && request&.xhr?
      return head(404)
    elsif !params[:id]
      flash[:error] = "Sorry, we couldn't find that notification."
      return redirect_to(notifications_path)
    end

    if summary_response.failed? && request&.xhr?
      return head(503)
    elsif summary_response.failed?
      flash[:error] = "#{params[:action].humanize} is not available at the moment."
      return redirect_to(notifications_path)
    end

    if summary.blank? && request&.xhr?
      return head(404)
    elsif summary.blank?
      flash[:error] = "Sorry, we couldn't find that notification."
      return redirect_to(notifications_path)
    end

    nil
  end

  memoize def summary_response
    GitHub.newsies.web.find_rollup_summary(params[:id]) if params[:id]
  end

  memoize def summary
    summary_response&.value
  end

  # Overrides RepositoryControllerMethods#repository_specified?
  def repository_specified?
    super || params[:repository_id]
  end

  # Overrides RepositoryControllerMethods#current_repository
  memoize def current_repository
    return @current_repository if @current_repository

    repo = if FeatureFlag.vexi.enabled?(:repos_domain_controllers, default: false)
      params[:repository_id] && Repositories.domain.by_id(params[:repository_id].to_i)
    else
      params[:repository_id] && Repository.find_by(id: params[:repository_id])
    end
    return repo if repo

    super
  end

  def validate_thread_subscription_events
    if params[:id] == "subscribe_to_custom_notifications" && invalid_thread_subscription_events.any?
      head(:bad_request)
    end
  end

  def validate_thread_types_set_when_using_custom_settings
    if params[:do] == "custom" && (!params.key?(:thread_types) || params[:thread_types] == [""])
      head(:bad_request)
    end
  end

  def thread_subscribe_action
    action = params[:id]

    if action == "subscribe_to_custom_notifications" && params[:events]&.filter_map(&:presence).blank?
      # The user has deselected the last custom notification event, so unsubscribe
      # them from the thread to reset their settings.
      action = "unsubscribe"
    end

    action
  end

  memoize def invalid_thread_subscription_events
    (params[:events]&.filter_map(&:presence) || []) - SUPPORTED_THREAD_SUBSCRIPTION_EVENTS
  end

  def valid_thread_subscription_events(thread)
    supported_events = SUPPORTED_THREAD_SUBSCRIPTION_EVENTS
    unless thread.is_a?(PullRequest) || (thread.is_a?(Issue) && thread.pull_request?)
      supported_events = supported_events.reject { |event| event == "merged" }
    end
    params[:events]&.filter_map(&:presence) & supported_events
  end

  memoize def valid_thread_type_subscriptions
    (params[:thread_types]&.filter_map(&:presence) & SUPPORTED_SUBSCRIPTION_THREAD_TYPES).map(&:constantize)
  end

  # Override this method so we don't check for external identities in public repos
  def require_active_external_identity_session?
    return super unless current_repository.present?

    current_repository.private?
  end

  def label_subscriptions_enabled?(repository, user)
    Notifyd::Flags.new(user).label_subscriptions?(repository)
  end

  # Bypass conditional access requirements for the watch_subscription fragment if the repository is public.
  def ip_allowlist_enforceable
    return :no if %w(watch_subscription).include?(action_name) && current_repository&.public
    super
  end

  # Bypass conditional access requirements for the watch_subscription fragment if the repository is public.
  def external_conditional_access_policy_enforceable
    return :no if %w(watch_subscription).include?(action_name) && current_repository&.public
    super
  end

  # Bypass two-factor authentication requirements for the watch_subscription fragment if the repository is public.
  def two_factor_enforceable
    return :no if %w(watch_subscription).include?(action_name) && current_repository&.public
    :yes
  end
end
