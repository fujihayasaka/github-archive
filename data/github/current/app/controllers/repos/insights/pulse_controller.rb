# typed: strict
# frozen_string_literal: true

class Repos::Insights::PulseController < GitContentController
  before_action :enforce_plan_supports_insights, only: [:index]
  before_action :ensure_flag_enabled
  layout "repository"

  sig { returns(String) }
  def self.react_bundle_name
    "repos-pulse"
  end

  stylesheet_bundle :insights

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:committer_data, :diffstat_summary, :overview_data]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  sig { void }
  def index # Main pulse page
    payload = IndexRoutePayload.new(
      committer_data_path: new_pulse_committer_data_path(current_repository.owner, current_repository),
      diffstat_summary_path: new_pulse_diffstat_summary_path(current_repository.owner, current_repository),
      overview_data_path: new_pulse_overview_data_path(current_repository.owner, current_repository)
    )
    respond_with_react(
      payload: payload,
      title: "Pulse · #{current_repository.name_with_display_owner}",
      layout: "layouts/repository/react_insights",
      page_data: {
        selected_link: :pulse,
      },
    )
  end

  sig { void }
  def overview_data # rubocop:todo GitHub/UseRestfulActions
    render_overview_data
  end

  sig { void }
  def committer_data # rubocop:todo GitHub/UseRestfulActions
    render_committer_data
  end

  sig { void }
  def diffstat_summary # rubocop:todo GitHub/UseRestfulActions
    render_diffstat_summary
  end

  private

  sig { void }
  def render_overview_data
    period = params[:period] || "weekly"
    view = Repositories::PulseView.new(current_repository, period, current_user)
    summary = view.summary

    # Prepare data for rendering

    range_label = safe_join([
        summary.since.strftime("%B %-d, %Y"),
        "–",
        Date.today.strftime("%B %-d, %Y"),
      ], " ")

    merged_pull_data = map_pull_data(summary.merged_pulls)
    new_pull_data = map_pull_data(summary.new_pulls)
    closed_issue_data = map_issue_data(summary.closed_issues)
    new_issue_data = map_issue_data(summary.new_issues)
    discussions_data = map_discussions_data(summary.active)
    releases_data = map_releases_data(summary.releases)

    render json: {
      period: view.period,
      rangeLabel: range_label,
      totalPullRequests: view.total_pull_requests,
      totalIssues: view.total_issues,
      mergedPulls: merged_pull_data,
      numAuthorsMergedPulls: summary.user_count_for(:merged_pulls),
      newPulls: new_pull_data,
      numAuthorsNewPulls: summary.user_count_for(:new_pulls),
      closedIssues: closed_issue_data,
      numAuthorsClosedIssues: summary.user_count_for(:closed_issues),
      newIssues: new_issue_data,
      numAuthorsNewIssues: summary.user_count_for(:new_issues),
      discussions: discussions_data,
      numAuthorsDiscussions: summary.active.size,
      releases: releases_data,
      numAuthorsReleases: summary.user_count_for(:releases),
    }
  rescue Repositories::Error => e
    Failbot.report!(e)
    render json: { error: "Unable to fetch pulse data" }, status: 500
  end

  sig { void }
  def render_committer_data
    summary = current_repository.activity_summary(viewer: current_user, period: params[:period])
    render json: summary.authors_with_commits
  end

  sig { void }
  def render_diffstat_summary
    period = params[:period] || "weekly"
    view = Repositories::PulseView.new(current_repository, period, current_user)

    if view.show_diffstat_summary?
      render json: {
        authorsWithCommits: view.summary.authors_with_commits.count,
        filesChanged: view.total_files_changed,
        additions: view.total_additions,
        deletions: view.total_deletions,
        masterCommits: view.total_default_branch_commits,
        totalCommits: view.summary.commit_count,
        defaultBranch: current_repository.default_branch,
        comparePathUrl: compare_path(current_repository, view.summary.range),
      }
    else
      # If no diffstat data is available, return fork path URL for frontend to handle
      fork_path_url = get_fork_path
      if fork_path_url
        render json: { forkPathUrl: fork_path_url }
      else
        render json: {} # No forking option should be shown
      end
    end
  rescue Repositories::Error => e
    Failbot.report!(e)
    render json: { error: "Unable to fetch diffstat summary" }, status: 500
  end

  class IndexRoutePayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "pulseRoute"
    end

    sig { params(committer_data_path: String, diffstat_summary_path: String, overview_data_path: String).void }
    def initialize(committer_data_path:, diffstat_summary_path:, overview_data_path:)
      @committer_data_path = committer_data_path
      @diffstat_summary_path = diffstat_summary_path
      @overview_data_path = overview_data_path
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        committerDataPath: @committer_data_path,
        diffstatSummaryPath: @diffstat_summary_path,
        overviewDataPath: @overview_data_path
      }
    end
  end

  # HELPERS

  sig { params(pulls: T.untyped).returns(T::Array[T::Hash[String, T.untyped]]) }
  def map_pull_data(pulls)
    pulls.map do |pull|
      {
        title: pull.title,
        createdAt: pull.created_at.utc.iso8601,
        number: pull.number,
        path: pull_request_path(pull)
      }
    end
  end

  sig { params(issues: T.untyped).returns(T::Array[T::Hash[String, T.untyped]]) }
  def map_issue_data(issues)
    issues.map do |issue|
      {
        title: issue.title,
        createdAt: issue.created_at.utc.iso8601,
        number: issue.number,
        path: issue_path(issue)
      }
    end
  end

  sig { params(discussions: T.untyped).returns(T::Array[T::Hash[String, T.untyped]]) }
  def map_discussions_data(discussions)
    discussions.map do |obj, comment_count|
      {
        title: obj.title,
        createdAt: obj.updated_at.utc.iso8601,
        number: obj.number,
        path: obj.url,
        commentCount: comment_count
      }
    end
  end

  sig { params(releases: T.untyped).returns(T::Array[T::Hash[String, T.untyped]]) }
  def map_releases_data(releases)
    releases.map do |release|
      {
        title: release.display_name,
        createdAt: release.published_at.utc.iso8601,
        number: release.tag_name,
        path: release_path(release)
      }
    end
  end

  sig { returns(T.nilable(String)) }
  def get_fork_path

    # only return fork path if forking is allowed
    return nil unless should_show_fork_option?

    if logged_in? && current_user.organizations.any?
      fork_select_path(current_repository.owner, current_repository)
    else
      fork_path(current_repository)
    end
  end

  sig { returns(T::Boolean) }
  def should_show_fork_option?
    forking_allowed? &&
    logged_in? &&
    current_repository.owner != current_user
  end

  # provide forking_allowed functionality
  sig { returns(T::Boolean) }
  def forking_allowed?
    details_view.forking_allowed?
  end

  # helper method to create the details view
  sig { returns(Repositories::DetailsView) }
  memoize def details_view
    @details_view ||= T.let(Repositories::DetailsView.new(
      repository: current_repository,
      repository_is_offline: repository_offline?,
      cap_view_filter: cap_view_filter,
      viewer_can_read_repo: current_user_can_read_repo?,
    ), T.nilable(Repositories::DetailsView))
  end

  sig { void }
  def ensure_flag_enabled
    if (
      !current_repository.feature_flag_enabled?(:repos_react_pulse_charts, default: false) &&
      !current_user&.feature_flag_enabled?(:repos_react_pulse_charts, default: false)
    )
      render_404
    end
  end

end
