# typed: true
# frozen_string_literal: true

class NotificationSubscriptionsController < ApplicationController
  before_action :login_required
  before_action :repository_name_filter, only: [:index]

  before_action :this_team_required, only: :create

  # Some notifications are not scoped to an organization, so we do conditional checks manually.
  # Needs investigation for protected organization access
  skip_before_action :perform_conditional_access_checks, only: [:index, :destroy, :dismiss_notice, :repository_filter] # rubocop:todo GitHub/DoNotSkipCapBeforeAction

  include PlatformHelper
  include ActionView::Helpers::TextHelper

  stylesheet_bundle :notifications

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Spokes,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:repository_filter]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  PAGE_SIZE = 25
  REPOSITORY_FILTER_SIZE = 250

  # The notification reasons we want to support filtering for in the UI
  REASONS_ALLOWLIST = Platform::Enums::NotificationReason.values.slice(
    "ASSIGN",
    "AUTHOR",
    "COMMENT",
    "MANUAL",
    "MENTION",
    "REVIEW_REQUESTED",
    "STATE_CHANGE",
    "TEAM_MENTION",
  ).freeze

  def index
    context_region_preset :notifications

    sort_direction = params[:sort] == "asc" ? :asc : :desc
    labels_by_sort_direction = { desc: "Most recently subscribed", asc: "Least recently subscribed" }

    if params[:reason].present?
      reason = params[:reason].upcase
      query_reason = reason if REASONS_ALLOWLIST.key?(reason)
    end

    resources_for_cap_filter = track_time(tags: ["method:index", "step:resources_for_cap_filter"]) do
      current_user.resources_for_cap_filter(
        direct_and_indirect_orgs: true
      )
    end

    unauthorized_resource_ids = track_time(tags: ["method:index", "step:unauthorized_resource_ids"]) do
      cap_filter.unauthorized_resource_ids(resources_for_cap_filter)
    end

    query = Platform::Helpers::NotificationThreadSubscriptionsQuery.new(
      viewer: current_user,
      direction: sort_direction,
      reason: query_reason,
      list_type: "Repository",
      list_id: selected_repository&.id,
      unauthorized_account_ids: unauthorized_resource_ids,
    )
    arguments = graphql_pagination_params(page_size: PAGE_SIZE)
    connection = Platform::ConnectionWrappers::NotificationThreadSubscriptions.new(
      query,
      first: arguments[:first],
      last: arguments[:last],
      before: arguments[:before],
      after: arguments[:after],
    )

    subscriptions = track_time(tags: ["method:index", "step:preload_subscriptions_data"]) do
      preload_subscriptions_data(connection.edge_nodes)
    end

    respond_to do |wants|
      wants.html do
        track_time(tags: ["method:index", "step:render"]) do
          render("notification_subscriptions/index", locals: {
            subscriptions: subscriptions,
            page_info: connection.page_info,
            subscription_count: connection.total_count,
            selected_repository: selected_repository,
            sort_direction: sort_direction,
            labels_by_sort_direction: labels_by_sort_direction,
            reason: reason,
            reasons: REASONS_ALLOWLIST.values,
            resources_for_cap_filter: resources_for_cap_filter,
          })
        end
      end
    end
  end

  def create
    state = case params[:reason]
    when "subscribed" then "subscribed"
    when "ignore" then "ignored"
    else "unsubscribed"
    end

    GitHub.newsies.process_subscription_update(
      subscribable: this_team,
      state: state,
      user: current_user
    )

    render json: { data: :success }
  end

  def destroy
    subscription_ids = Array(params[:subscription_ids]).take(PAGE_SIZE)

    response = Notifications::Subscriptions.delete_thread_subscriptions(
      user_id: current_user.id,
      thread_subscription_ids: subscription_ids
    )

    if response.success?
      flash[:notice] = "You’ve been unsubscribed from #{pluralize(subscription_ids.length, "thread")}."
    else
      flash[:error] = "Unsubscribe is not available at the moment."
    end

    redirect_to :back
  end

  def dismiss_notice # rubocop:todo GitHub/UseRestfulActions
    current_user.dismiss_notice("notification_thread_subscriptions_notice")
    redirect_to notification_subscriptions_path
  end

  def repository_filter # rubocop:todo GitHub/UseRestfulActions
    subscribed_repo_ids = GitHub.newsies.thread_subscription_lists(
      user_id: current_user.id,
      list_type: "Repository",
    ).value.sort_by { |_, count| count }.take(REPOSITORY_FILTER_SIZE).map { |list, _| list.id }

    repos = Repository.
      not_owned_by(cap_filter.unauthorized_resource_ids(current_user.resources_for_cap_filter)).
      where(id: subscribed_repo_ids)

    readable_repos = Promise.all(repos.map do |repo|
      repo.async_readable_by?(current_user).then { |readable| repo if readable }
    end).sync.compact

    filter_params = params.slice(:subscription_params).permit(subscription_params: [:sort, :reason, :repository])

    respond_to do |format|
      format.any(:html, :html_fragment) do
        render partial: "notification_subscriptions/repository_filter", locals: {
          subscription_params: filter_params[:subscription_params]&.to_h || {},
          lists: readable_repos,
        }, layout: false, formats: [:html, :html_fragment]
      end
    end
  end

  private

  private def selected_repository
    return if params[:repository].blank?
    return @selected_repository if defined? @selected_repository

    @selected_repository = typed_object_from_id([Platform::Objects::Repository], params[:repository])
  rescue Platform::Errors::NotFound
    @selected_repository = nil
  end

  # Redirects ?repository_name=foo/bar&... to ?repository={global_relay_id}&...
  # if the repo is accessible. If not accessible or requires conditional access,
  # will redirect without a repository filter and render a flash.
  def repository_name_filter
    return unless params[:repository_name].present?

    filter_params = params.slice(:reason, :repository, :sort).permit(:reason, :repository, :sort).to_h
    owner, name = params[:repository_name].split("/")

    unless owner.present? && name.present?
      flash[:notice] = "To filter subscriptions enter a full repository name for example: twbs/bootstrap."
      return redirect_to notification_subscriptions_path(filter_params.merge(repository: nil))
    end

    repo = Repository.nwo(owner, name)

    unless repo&.visible_and_readable_by?(current_user)
      flash[:notice] = "#{params[:repository_name]} does not exist."
      return redirect_to notification_subscriptions_path(filter_params.merge(repository: nil))
    end

    unauthorized_ip_account_ids = cap_filter.unauthorized_resource_ids(
      current_user&.resources_for_cap_filter, only: [:ip_allowlist, :external_conditional_access_policy]
    )

    if unauthorized_ip_account_ids.include?(repo.owner.id)
      flash[:notice] = "Viewing subscriptions for #{params[:repository_name]} requires an allowed IP address."
      return redirect_to notification_subscriptions_path(filter_params.merge(repository: nil))
    end

    unauthorized_sso_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations, only: :saml)
    if unauthorized_sso_org_ids.include?(repo.owner.id)
      flash[:notice] = "Viewing subscriptions for #{params[:repository_name]} requires single sign-on."
      return redirect_to notification_subscriptions_path(filter_params.merge(repository: nil))
    end

    redirect_to notification_subscriptions_path(filter_params.merge(repository: repo.global_relay_id))
  end

  def target_for_conditional_access
    # login is required, so no need to do CAP - we will 404 regardless
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    if this_team
      this_team.organization
    else
      # team not found
      raise NotImplementedError, "Only Team is currently supported"
    end
  end

  memoize def this_team
    typed_object_from_id([Platform::Objects::Team], params[:list_id])
  rescue Platform::Errors::NotFound
    nil
  end

  def this_team_required
    render_404 unless this_team
  end

  def preload_subscriptions_data(subscriptions)
    subscriptions_data = []

    Promise.all(subscriptions.map do |subscription|
      subscription.async_thread.then do |thread|
        next unless thread.present?
        thread.async_repository.then do |repo|
          next unless repo.present?
          subscriptions_data.push([subscription, thread, repo])

          preloads = []
          preloads << thread.async_issue if thread.is_a?(::PullRequest)
          preloads << thread.async_user

          Promise.all(preloads)
        end
      end
    end).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    subscriptions_data.sort_by { |subscription, _thread, _repo| subscriptions.index(subscription) }
  end
end
