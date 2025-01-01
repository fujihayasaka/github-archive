# typed: false
# frozen_string_literal: true

class GraphsController < GitContentController
  before_action :ensure_repository_not_empty, except: [
    :index,
    :languages,
    :community,
    :contributions_data,
    :discussions_daily_contributors_data,
    :discussions_new_contributors_data,
    :discussions_page_views_data
  ]
  before_action :pushers_only, only: [:traffic, :traffic_data, :clone_activity_data]
  before_action :enforce_can_access_community, only: [
    :community,
    :contributions_data,
    :discussions_daily_contributors_data,
    :discussions_new_contributors_data,
    :discussions_page_views_data
  ]
  before_action :enforce_plan_supports_insights, only: [:traffic, :traffic_data, :commit_activity, :commit_activity_data]
  skip_before_action :ask_the_gitkeeper, only: :community
  layout "repository"

  stylesheet_bundle :insights

  include GitHub::RateLimitedRequest

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
    only: [:traffic]

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
    only: [:commit_activity]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    only: [:commit_activity_data]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:community]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    only: [:contributions_data]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    only: [:discussions_daily_contributors_data]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    only: [:discussions_new_contributors_data]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    only: [:discussions_page_views_data]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    only: [:languages]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
    only: [:traffic_data]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [
      :index,
      :commit_activity,
      :community,
      :traffic
    ],
    optional: true

  def index
    redirect_to pulse_path
  end

  def languages # rubocop:todo GitHub/UseRestfulActions
    redirect_to repository_path(current_repository), status: 301
  end

  def commit_activity # rubocop:todo GitHub/UseRestfulActions
    if override_legacy_url_enabled
      # This is copied from Repos::Insights::CommitActivityController#index temporarily
      # to ensure backcompat so the backend can be deployed before the frontend
      payload = Repos::Insights::CommitActivityController::IndexRoutePayload.new(graph_data_path: commit_activity_data_path)
      respond_with_react(
        app_name: "repos-commit-activity",
        payload: payload,
        title: "Commits · #{current_repository.name_with_display_owner}",
        layout: "layouts/repository/react_insights",
        page_data: {
          selected_link: :repo_graphs,
        },
      )
    else
      redirect_to controller: "repos/insights/commit_activity", action: "index"
    end
  end

  def commit_activity_data # rubocop:todo GitHub/UseRestfulActions
    if data = GitHub::RepoGraph.commit_activity_data(current_repository,
        viewer: current_user,
        cache_only: robot?)
      render json: data
    else
      head 202
    end
  rescue GitHub::RepoGraph::UnusableDataError
    render json: { unusable: true }
  end

  def clone_activity_data # rubocop:todo GitHub/UseRestfulActions
    time_range = traffic_data_time_range

    # No-op request to new service for load testing
    GitHub.hydro_aggregation_api_client.repo_clones(
      repo_id: current_repository.id,
      from: time_range.first,
    )

    counts = GitHub.dogstats.time "graph", tags: ["action:clones"] do
      response = GitHub.pond_client.counts(
        current_repository.id,
        Pond::EventType::CLONE,
        Pond::Granularity::DAY,
        { from: time_range.first.to_i * 1000, to: time_range.last.to_i * 1000 })
      Pond.format_time_series(
        data: response.data["data"],
        from: time_range.first,
        to: time_range.last,
        event_type: Pond::EventType::CLONE
      )
    end

    render json: counts
  rescue Octolytics::Error => error
    Failbot.report!(error)
    head 500
  end

  def traffic # rubocop:todo GitHub/UseRestfulActions
    strip_analytics_query_string

    if "top_lists" == params[:partial] || "#top-domains" == request.headers["X-PJAX-Container"]
      view = Repositories::Graph::TrafficView.new(
        current_repository,
        current_user,
        params[:referrer],
      )

      respond_to do |format|
        format.html do
          if "top_lists" == params[:partial]
            render partial: "graphs/top_lists", locals: { view: view }
          elsif !view.show_referrer_paths?
            render partial: "graphs/referring_sites", locals: { view: view }
          else
            render partial: "graphs/referrer_paths", locals: { view: view }
          end
        end
      end
    else
      if (
        current_repository.feature_flag_enabled?(:repos_react_traffic_charts, default: false) ||
        current_user&.feature_flag_enabled?(:repos_react_traffic_charts, default: false)
      )
        if override_legacy_url_enabled
          payload = Repos::Insights::TrafficController::IndexRoutePayload.new(graph_data_path: new_traffic_data_path)
          respond_with_react(
            app_name: "repos-traffic",
            payload: payload,
            title: "Traffic · #{current_repository.name_with_display_owner}",
            layout: "layouts/repository/react_insights"
          )
        else
          redirect_to controller: "repos/insights/traffic", action: "index"
        end
        return
      end
      render "graphs/traffic"
    end
  end

  def traffic_data # rubocop:todo GitHub/UseRestfulActions
    time_range = traffic_data_time_range

    # No-op request to new service for load testing
    GitHub.hydro_aggregation_api_client.repo_page_views(
      repo_id: current_repository.id,
      from: time_range.first,
    )

    counts = GitHub.dogstats.time "graph", tags: ["action:traffic"] do
      response = GitHub.pond_client.counts(
        current_repository.id,
        Pond::EventType::VIEW,
        Pond::Granularity::DAY,
        { from: time_range.first.to_i * 1000, to: time_range.last.to_i * 1000 })
      Pond.format_time_series(
        data: response.data["data"],
        from: time_range.first,
        to: time_range.last,
        event_type: Pond::EventType::VIEW
      )
    end
    render json: counts
  rescue Octolytics::Error => error
    Failbot.report!(error)
    head 500
  end

  def community # rubocop:todo GitHub/UseRestfulActions
    valid_periods = CommunityInsightsDailyCount::PERIODS.keys

    unless valid_periods.include?(graph_period)
      flash[:error] = "Sorry, that isn't a valid time period to fetch data for."
      return redirect_to community_graph_path
    end

    render "graphs/community"
  end

  def contributions_data # rubocop:todo GitHub/UseRestfulActions
    data = GitHub.cache.fetch(community_insights_cache_key("contributions_data")) do
      counts = CommunityInsightsDailyCount.all_for_period(current_repository, graph_period)

      next [] if counts.empty?

      data = [
        { name: "discussions", class: "discussions-line", delta: 0, data: [] },
        { name: "issues", class: "issues-line", delta: 100, data: [] },
        { name: "pull requests", class: "pull-requests-line", delta: 170, data: [] },
      ]

      # We have sparse data so we need to fill in the gaps
      end_time = DateTime.now.beginning_of_day
      start_time = end_time - CommunityInsightsDailyCount::PERIODS[graph_period]

      (start_time..end_time).each_slice(CommunityInsightsDailyCount::PERIOD_SPLIT_SIZES[graph_period]) do |slice|
        date = slice.first.to_i * 1000
        chunk = counts.select { |e| e.entry_date >= slice.first && e.entry_date <= slice.last }

        data[0][:data] << {
          date: date,
          value: chunk.map { |e| e.discussions_count }.sum,
          type: "discussions"
        }

        data[1][:data] << {
          date: date,
          value: chunk.map { |e| e.issues_count }.sum,
          type: "issues"
        }

        data[2][:data] << {
          date: date,
          value: chunk.map { |e| e.pull_requests_count }.sum,
          type: "pull requests"
        }
      end
      data
    end

    return render json: { error: "No data available" }, status: :not_found if data.empty?
    # If all values are 0, we don't want to show the graph

    if data.pluck(:data).flatten.map { |d| d[:value] }.sum.zero?
      return render json: { error: "No data available" }, status: :not_found
    end

    render json: data
  end

  def discussions_daily_contributors_data # rubocop:todo GitHub/UseRestfulActions
    data = GitHub.cache.fetch(community_insights_cache_key("discussions_daily_contributors_data")) do
      fetch_contributors_data(new_count: false)
    end

    return render json: { error: "No data available" }, status: :not_found if data.empty?
    render json: data
  end

  def discussions_new_contributors_data # rubocop:todo GitHub/UseRestfulActions
    data = GitHub.cache.fetch(community_insights_cache_key("discussions_new_contributors_data")) do
      fetch_contributors_data(new_count: true)
    end

    return render json: { error: "No data available" }, status: :not_found if data.empty?
    render json: data
  end

  def discussions_page_views_data # rubocop:todo GitHub/UseRestfulActions
    data = GitHub.cache.fetch(community_insights_cache_key("discussions_page_views_data")) do
      counts = CommunityInsightsDailyCount.all_for_period(current_repository, graph_period)

      next [] if counts.empty?

      data = [
        { name: "logged in", class: "logged-in-views", delta: 170, data: [] },
        { name: "anonymous", class: "anonymous-views", delta: 80, data: [] },
      ]

      # We have sparse data so we need to fill in the gaps
      end_time = DateTime.now.beginning_of_day
      start_time = end_time - CommunityInsightsDailyCount::PERIODS[graph_period]

      (start_time..end_time).each_slice(CommunityInsightsDailyCount::PERIOD_SPLIT_SIZES[graph_period]) do |slice|
        date = slice.first.to_i * 1000
        chunk = counts.select { |e| e.entry_date >= slice.first && e.entry_date <= slice.last }

        data[0][:data] << {
          date: date,
          value: chunk.map { |e| e.discussion_logged_in_page_view_count }.sum,
          type: "logged in"
        }

        data[1][:data] << {
          date: date,
          value: chunk.map { |e| e.discussion_anonymous_page_view_count }.sum,
          type: "anonymous"
        }
      end
      data
    end

    return render json: { error: "No data available" }, status: :not_found if data.empty?
    # If all values are 0, we don't want to show the graph
    if data.pluck(:data).flatten.map { |d| d[:value] }.sum.zero?
      return render json: { error: "No data available" }, status: :not_found
    end

    render json: data
  end

  private

  def enforce_can_access_community
    render_404 unless current_repository.can_view_community_insights?(current_user)
  end

  def handle_skipmc_for(graph_name)
    if GitHub.cache.skip
      GitHub::RepoGraph.clear_cache(current_repository, graph_name)
    end
  end

  def ensure_repository_not_empty
    if current_repository.empty?
      render_404
    end
  end

  def traffic_data_time_range
    # Graphs use the UTC+0 timezone to roll up a 'day'.  We want 14 total days
    # worth of data so we ask for the previous 6 days + today.
    from = 13.days.ago.utc.beginning_of_day
    # Round down to last complete hour
    to = Time.now.utc.change(min: 0)

    (from..to)
  end

  def community_insights_cache_key(graph_string)
    @updated_at ||= CommunityInsightsDailyCount.where(repository_id: current_repository.id).order(updated_at: :desc).first&.updated_at
    "#{graph_string}:v1:#{graph_period}:#{current_repository.id}:#{@updated_at}"
  end

  def fetch_contributors_data(new_count: false)
    return {} unless CommunityInsightsDailyCount::PERIODS.keys.include?(graph_period)

    counts = CommunityInsightsDailyCount.all_for_period(current_repository, graph_period)

    return {} if counts.empty?

    data = [
      { name: "contributors", class: "contributors-line", delta: 0, data: [] },
    ]

    # We have sparse data so we need to fill in the gaps
    end_time = DateTime.now.beginning_of_day
    start_time = end_time - CommunityInsightsDailyCount::PERIODS[graph_period]

    (start_time..end_time).each_slice(CommunityInsightsDailyCount::PERIOD_SPLIT_SIZES[graph_period]) do |slice|
      date = slice.first.to_i * 1000
      chunk = counts.select { |e| e.entry_date >= slice.first && e.entry_date <= slice.last }

      data[0][:data] << {
        date: date,
        value: chunk.map { |e| new_count ? e.discussion_new_contributor_count : e.discussion_contributors_count }.sum,
        type: "contributors"
      }
    end

    if data.pluck(:data).flatten.map { |d| d[:value] }.sum.zero?
      return {}
    end

    data
  end

  def graph_period
    params.fetch(:period, "last_30_days").to_sym
  end

  def is_using_contribution_insights?
    GitHub::RepoGraph.use_insights?(viewer: current_user, repository: current_repository, cache_only: robot?)
  end

  sig { returns(T::Boolean) }
  def override_legacy_url_enabled
    current_repository.feature_flag_enabled?(:repos_insights_remove_new_url, default: false) ||
      current_user&.feature_flag_enabled?(:repos_insights_remove_new_url, default: false)
  end
end
