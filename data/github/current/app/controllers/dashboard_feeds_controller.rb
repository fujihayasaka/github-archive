# typed: true
# frozen_string_literal: true

class DashboardFeedsController < ApplicationController
  include OrganizationsHelper

  before_action :login_required
  before_action :org_members_only_org_feed, only: %w( show )
  around_action :record_request_time, only: :show

  helper_method :conduit_enabled?

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Profiles,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  stylesheet_bundle :dashboard
  javascript_bundle :dashboard

  def show
    GitHub.dogstats.distribution_time("dashboard_feed.page.response_time", tags: dashboard_page_tags("success:true")) do
      render_feed

      GitHub.dogstats.increment("dashboard_feed.page.requests.count", tags: dashboard_page_tags("success:true"))
    end
  rescue StandardError => e
    GitHub.dogstats.increment("dashboard_feed.page.requests.count", tags: dashboard_page_tags("success:false"))
    raise e
  end

  def record_request_time # rubocop:todo GitHub/UseRestfulActions
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    yield

    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    GitHub.dogstats.distribution("dashboard_feeds.dist.time", (end_time - start_time) * 1_000)
  end

  private

  def render_feed
    conduit_enabled? ? render_conduit_show : render_stratocaster_show
  end

  def render_conduit_show
    respond_to do |format|
      format.html do
        render "dashboard_feeds/show", layout: !request.xhr? && !pjax?
      end
    end
  end

  def render_stratocaster_show
    return render partial: "events/unavailable" if events_timeline.unavailable?

    # Allows us to turn off expensive queries causing the dashboard to load slowly
    # for more information please see https://github.com/github/github/issues/93044.
    starred_repo_ids = if show_star_repo_buttons?
      get_starred_repo_ids
    end

    starrable_repo_ids = if show_star_repo_buttons?
      get_starrable_repo_ids(event_repos: view_model.event_repos, starred_repo_ids: starred_repo_ids)
    end

    followed_user_ids = if show_follow_user_buttons?
      get_followed_user_ids
    end

    if show_sponsored_user_buttons?
      sponsored_user_ids = get_sponsored_user_ids
      sponsorable_user_ids = get_sponsorable_user_ids
    end

    discussion_number_and_comment_count_by_release_id = if show_release_discussions?
      get_discussion_number_and_comment_count_by_release_id
    end

    reaction_count_by_content_by_release_id = get_reaction_count_by_content_by_release_id
    viewer_reaction_contents_by_release_id = get_viewer_reaction_contents_by_release_id

    respond_to do |format|
      format.html do
        render "dashboard_feeds/show", locals: {
          followed_user_ids: followed_user_ids,
          following_count: current_user.following_count(viewer: current_user),
          starred_repo_ids: starred_repo_ids,
          starrable_repo_ids: starrable_repo_ids,
          sponsored_user_ids: sponsored_user_ids,
          sponsorable_user_ids: sponsorable_user_ids,
          discussion_number_and_comment_count_by_release_id: discussion_number_and_comment_count_by_release_id,
          reaction_count_by_content_by_release_id: reaction_count_by_content_by_release_id,
          viewer_reaction_contents_by_release_id: viewer_reaction_contents_by_release_id,
          view_model: view_model,
        }, layout: !request.xhr? && !pjax?
      end
    end
  end

  def conduit_enabled?
    GitHub.conduit_enabled?
  end

  def dashboard_page_tags(success_tag)
    [
      "source:dashboard_page",
      success_tag,
      "xhr:#{request.xhr?}",
      "pjax:#{pjax?}"
    ]
  end

  memoize def view_model
    Dashboard::NewsFeedView.new(
      current_user: current_user,
      timeline: events_timeline,
      page: current_page
    )
  end

  sig { params(event_repos: T::Array[Repository], starred_repo_ids: T.nilable(T::Set[Integer])).returns(T::Array[Integer]) }
  def get_starrable_repo_ids(event_repos:, starred_repo_ids: nil)
    if GitHub.email_verification_enabled? && current_user.must_verify_email?
      return []
    end

    starred = starred_repo_ids || Set.new
    async_starrable_repo_ids = event_repos.each_with_object([]) do |repo, promises|
      next if repo.id.in?(starred)

      promises << repo.async_can_star?(current_user).then do |can_star|
        repo.id if can_star
      end
    end

    Promise.all(async_starrable_repo_ids).sync.compact
  rescue => e
    GitHub.logger.warn("Failed to load starrable repo ids: #{e.message}")
    GitHub.dogstats.increment("dashboard_feed.enrichment.failed", tags: ["enrichment:starrable_repo_ids"])
    []
  end

  def show_star_repo_buttons?
    current_organization.nil?
  end

  def event_repo_ids
    GitHub.dogstats.distribution_time("dashboard.get_event_repo_ids.time") do
      view_model.event_repo_ids
    end
  end

  def show_follow_user_buttons?
    current_organization.nil?
  end

  def show_release_discussions?
    current_organization.nil?
  end

  def followable_user_ids
    GitHub.dogstats.distribution_time("dashboard.get_followable_user_ids.time") do
      view_model.followable_user_ids(viewer: current_user)
    end
  end

  def show_sponsored_user_buttons?
    GitHub.sponsors_enabled? &&
      current_organization.nil?
  end

  def org_members_only_org_feed
    if org_login_param
      render_404 if current_organization.nil?
    end
  end

  sig { returns(T::Set[Integer]) }
  def get_starred_repo_ids
    GitHub.dogstats.distribution_time("dashboard.get_starred_repo_ids.time") do
      Star.starred_repository_ids_from(user: current_user, repository_ids: event_repo_ids)
    end
  rescue => e
    GitHub.logger.warn("Failed to load starred repo ids: #{e.message}")
    GitHub.dogstats.increment("dashboard_feed.enrichment.failed", tags: ["enrichment:starred_repo_ids"])
    Set.new
  end

  sig { returns(T::Array[Integer]) }
  def get_followed_user_ids
    GitHub.dogstats.distribution_time("dashboard.get_followed_user_ids.time") do
      Following.followed_by(current_user).where(following_id: followable_user_ids).pluck(:following_id)
    end
  rescue => e
    GitHub.logger.warn("Failed to load followed user ids: #{e.message}")
    GitHub.dogstats.increment("dashboard_feed.enrichment.failed", tags: ["enrichment:followed_user_ids"])
    []
  end

  sig { returns(T::Set[Integer]) }
  def get_sponsored_user_ids
    return Set.new if sponsor_button_target_user_ids.empty?

    GitHub.dogstats.distribution_time("dashboard.get_sponsored_user_ids.time") do
      sponsorable_ids = current_user.active_sponsorships_as_sponsor_relation
        .with_user_or_org_sponsorable(sponsor_button_target_user_ids)
        .pluck(:sponsorable_id)
      Set.new(sponsorable_ids)
    end
  rescue => e
    GitHub.logger.warn("Failed to load sponsored user ids: #{e.message}")
    GitHub.dogstats.increment("dashboard_feed.enrichment.failed", tags: ["enrichment:sponsored_user_ids"])
    Set.new
  end

  sig { returns(T::Set[Integer]) }
  def get_sponsorable_user_ids
    return Set.new if sponsor_button_target_user_ids.empty?

    GitHub.dogstats.distribution_time("dashboard.get_sponsorable_user_ids.time") do
      User.sponsorable_user_ids_from(sponsor_button_target_user_ids, viewer: current_user)
    end
  rescue => e
    GitHub.logger.warn("Failed to load sponsorable user ids: #{e.message}")
    GitHub.dogstats.increment("dashboard_feed.enrichment.failed", tags: ["enrichment:sponsorable_user_ids"])
    Set.new
  end

  # Fetch sponsor button targets for events in this feed. We'll defer confirming
  # which of these users are actually sponsorable for a batch query rather than
  # generating an individual query for each event.
  memoize def sponsor_button_target_user_ids
    view_model.events_from_grouped_events.filter_map do |event|
      event.try(:sponsor_button_target_user_id)
    end
  end

  sig { returns(T::Hash[Integer, T::Array[T.untyped]]) }
  def get_discussion_number_and_comment_count_by_release_id
    Discussion.
      where(release_id: view_model.release_ids).
      pluck(:release_id, :number, :comment_count).
      each_with_object({}) do |(release_id, discussion_number, comment_count), result|
        result[release_id] = [discussion_number, comment_count]
      end
  rescue => e
    GitHub.logger.warn("Failed to load discussion counts by release: #{e.message}")
    GitHub.dogstats.increment("dashboard_feed.enrichment.failed", tags: ["enrichment:discussion_count_by_release"])
    {}
  end

  sig { returns(T::Hash[Integer, T::Hash[String, Integer]]) }
  def get_reaction_count_by_content_by_release_id
    Reaction.
      where(subject_type: "Release", subject_id: view_model.release_ids).
      group(:subject_id, :content).
      count.
      each_with_object({}) do |((release_id, content), reaction_count), result|
        result[release_id] ||= {}
        result[release_id][content] = reaction_count
      end
  rescue => e
    GitHub.logger.warn("Failed to load reaction counts by release: #{e.message}")
    GitHub.dogstats.increment("dashboard_feed.enrichment.failed", tags: ["enrichment:reaction_count_by_release"])
    {}
  end

  sig { returns(T::Hash[Integer, T::Array[String]]) }
  def get_viewer_reaction_contents_by_release_id
    Reaction.
      where(subject_type: "Release", subject_id: view_model.release_ids, user: current_user).
      pluck(:subject_id, :content).
      each_with_object({}) do |(release_id, content), result|
        result[release_id] ||= []
        result[release_id].push(content)
      end
  rescue => e
    GitHub.logger.warn("Failed to load viewer reaction contents by release: #{e.message}")
    GitHub.dogstats.increment("dashboard_feed.enrichment.failed", tags: ["enrichment:viewer_reaction_contents_by_release"])
    {}
  end

  def events_timeline_key
    if current_organization
      "org:#{current_organization.id}"
    else
      "user:#{current_user.id}"
    end
  end
end
