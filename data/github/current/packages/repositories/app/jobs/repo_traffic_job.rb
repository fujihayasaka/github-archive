# typed: true
# frozen_string_literal: true

require "monolith-twirp-reposinsights-reposinsights"

class RepoTrafficJob < ApplicationJob
  queue_as :repo_traffic
  retry_on_dirty_exit

  locked_by timeout: 20.minutes, key: ->(job) {
    job.arguments[0]
  }

  def perform(repo_id)
    # only runs on dotcom
    return if GitHub.enterprise? || GitHub.multi_tenant_enterprise?

    repo = Repository.find_by(id: repo_id)
    return if !repo || !GitHub.repos_insights_enabled?(repo)

    # returned format in `.second` is [["2024-06-30"]]
    actual_latest_run_day = GitHub.trino.run(dag_run_query)&.second&.first&.first
    return unless actual_latest_run_day

    # the DAG runs at midnight UTC and aggregates yesterday's data, so the status is completed as of "today"
    # but the data in each table is for the previous date.
    actual_latest_run_date = Date.strptime(actual_latest_run_day, "%Y-%m-%d")

    @latest_date = actual_latest_run_date - 1.day
    @latest_day = @latest_date.strftime("%Y-%m-%d")

    @timeseries_first_date = @latest_date - 13.days
    @timeseries_first_day = @timeseries_first_date.strftime("%Y-%m-%d")

    page_views_timeseries = GitHub.trino.run_with_names(page_views_timeseries_query(repo.id))
    clones_timeseries = GitHub.trino.run_with_names(clones_timeseries_query(repo.id))
    traffic_summary = GitHub.trino.run_with_names(traffic_summary_query(repo.id))
    top_content = GitHub.trino.run_with_names(top_content_query(repo.id))
    top_referrers = GitHub.trino.run_with_names(top_referrers_query(repo.id))

    summary_14d = build_summary_14d(traffic_summary)
    daily_metrics = build_daily_metrics(page_views_timeseries, clones_timeseries)
    top_content = build_top_content(top_content)
    top_referrers = build_top_referrers(top_referrers)

    twirp_request = MonolithTwirp::ReposInsights::ReposInsights::V1::UpsertRepoTrafficRequest.new(
      traffic_data: MonolithTwirp::ReposInsights::ReposInsights::V1::RepoTrafficData.new(
        id: repo.id,
        last_updated: @latest_day,
        summary_14d: summary_14d,
        daily_metrics: daily_metrics,
        top_content: top_content,
        top_referrers: top_referrers,
      )
    )

    GitHub.repos_insights_client.upsert_repo_traffic_data(twirp_request)
  end

  # gets the day of the latest run for both DAGs
  def dag_run_query
    %Q(
      SELECT day
      FROM (
          (SELECT day, MAX(timestamp) AS max_timestamp
          FROM delta.hydro.airflow_v0_dag_run_state
          WHERE dag_id = 'repo_topn'
            AND state = 'success'
          GROUP BY day
          ORDER BY max_timestamp DESC
          LIMIT 1)

          UNION ALL

          (SELECT day, MAX(timestamp) AS max_timestamp
          FROM delta.hydro.airflow_v0_dag_run_state
          WHERE dag_id = 'repo_timeseries'
            AND state = 'success'
          GROUP BY day
          ORDER BY max_timestamp DESC
          LIMIT 1)
      )
      ORDER BY max_timestamp ASC
      LIMIT 1
    )
  end

  def page_views_timeseries_query(repo_id)
    %Q(
      SELECT
        day,
        COALESCE(num_unique_viewers, 0) AS num_unique_viewers,
        COALESCE(num_page_views, 0)     AS num_page_views
      FROM delta.github_dotcom.repo_traffic_page_views
      WHERE repository_id = #{repo_id}
        AND day BETWEEN '#{@timeseries_first_day}' AND '#{@latest_day}'
    )
  end

  def clones_timeseries_query(repo_id)
    %Q(
      SELECT
        day,
        COALESCE(num_unique_cloners, 0) AS num_unique_cloners,
        COALESCE(num_clones, 0)         AS num_clones
      FROM delta.github_dotcom.repo_traffic_repo_clones
      WHERE repository_id = #{repo_id}
        AND day BETWEEN '#{@timeseries_first_day}' AND '#{@latest_day}'
      ORDER BY repository_id, day
    )
  end

  def traffic_summary_query(repo_id)
    %Q(
      SELECT
        COALESCE(pv.day, cl.day)   AS day,
        pv.num_unique_viewers_14d,
        pv.num_page_views_14d,
        cl.num_unique_cloners_14d,
        cl.num_clones_14d
      FROM (
        SELECT *
        FROM delta.github_dotcom.repo_traffic_page_views_summary
        WHERE repository_id = #{repo_id}
          AND day = '#{@latest_day}'
      ) pv
      FULL OUTER JOIN (
        SELECT *
        FROM delta.github_dotcom.repo_traffic_repo_clones_summary
        WHERE repository_id = #{repo_id}
          AND day = '#{@latest_day}'
      ) cl
          ON pv.repository_id = cl.repository_id
            AND pv.day = cl.day
    )
  end

  def top_content_query(repo_id)
    %Q(
      WITH ranked_content AS (
        SELECT
          day,
          path,
          title,
          num_page_views,
          num_unique_viewers,
          row_number() OVER (
              PARTITION BY repository_id, day
              ORDER BY num_page_views DESC, num_unique_viewers DESC, path
          ) AS rn
        FROM delta.github_dotcom.repo_traffic_top_content
        WHERE repository_id = #{repo_id}
          AND day = '#{@latest_day}'
      )
      SELECT
        day,
        path,
        title,
        num_page_views,
        num_unique_viewers,
        rn
      FROM ranked_content
      WHERE rn <= 10
    )
  end

  def top_referrers_query(repo_id)
    %Q(
      WITH ranked_referrers AS (
        SELECT
          day,
          referrer,
          search_engine,
          num_page_views,
          num_unique_viewers,
          row_number() OVER (
              PARTITION BY repository_id, day
              ORDER BY num_page_views DESC, num_unique_viewers DESC, referrer
          ) AS rn
        FROM delta.github_dotcom.repo_traffic_top_referrers
        WHERE repository_id = #{repo_id}
          AND day = '#{@latest_day}'
      )
      SELECT
        day,
        referrer,
        search_engine,
        num_page_views,
        num_unique_viewers,
        rn
      FROM ranked_referrers
      WHERE rn <= 10
    )
  end

  private

  # total counts over the last 14 days
  sig { params(traffic_summary: T.untyped).returns(T.nilable(MonolithTwirp::ReposInsights::ReposInsights::V1::TrafficSummary14d)) }
  def build_summary_14d(traffic_summary)
    # result should only have a single row with the latest day
    summary_row = traffic_summary.first
    return nil unless summary_row

    MonolithTwirp::ReposInsights::ReposInsights::V1::TrafficSummary14d.new(
      page_views: MonolithTwirp::ReposInsights::ReposInsights::V1::PageViewMetrics.new(
        num_page_views: summary_row["num_page_views_14d"] || 0,
        num_unique_viewers: summary_row["num_unique_viewers_14d"] || 0,
      ),
      clones: MonolithTwirp::ReposInsights::ReposInsights::V1::CloneMetrics.new(
        num_clones: summary_row["num_clones_14d"] || 0,
        num_unique_cloners: summary_row["num_unique_cloners_14d"] || 0,
      ),
    )
  end

  # individual daily metrics for the last 14 days
  sig { params(page_views_timeseries: T.untyped, clones_timeseries: T.untyped).returns(T::Array[MonolithTwirp::ReposInsights::ReposInsights::V1::DailyMetric]) }
  def build_daily_metrics(page_views_timeseries, clones_timeseries)
    metrics = []

    # loop through each date and generate a metric from each timeseries
    @timeseries_first_date.upto(@latest_date) do |date|
      day_str = date.strftime("%Y-%m-%d")
      page_view_row = page_views_timeseries.find { |row| row["day"] == day_str }
      clone_row = clones_timeseries.find { |row| row["day"] == day_str }

      metrics << MonolithTwirp::ReposInsights::ReposInsights::V1::DailyMetric.new(
        day: day_str,
        page_views: MonolithTwirp::ReposInsights::ReposInsights::V1::PageViewMetrics.new(
          num_page_views: page_view_row ? page_view_row["num_page_views"] || 0 : 0,
          num_unique_viewers: page_view_row ? page_view_row["num_unique_viewers"] || 0 : 0,
        ),
        clones: MonolithTwirp::ReposInsights::ReposInsights::V1::CloneMetrics.new(
          num_clones: clone_row ? clone_row["num_clones"] || 0 : 0,
          num_unique_cloners: clone_row ? clone_row["num_unique_cloners"] || 0 : 0,
        ),
      )
    end

    metrics
  end

  sig { params(top_content: T.untyped).returns(T::Array[MonolithTwirp::ReposInsights::ReposInsights::V1::TopContent]) }
  def build_top_content(top_content)
    top_content
      .sort_by { |row| row["rn"] }
      .map do |row|
        MonolithTwirp::ReposInsights::ReposInsights::V1::TopContent.new(
          path: row["path"],
          title: row["title"] || "",
          num_page_views: row["num_page_views"] || 0,
          num_unique_viewers: row["num_unique_viewers"] || 0,
        )
      end
  end

  sig { params(top_referrers: T.untyped).returns(T::Array[MonolithTwirp::ReposInsights::ReposInsights::V1::TopReferrer]) }
  def build_top_referrers(top_referrers)
    top_referrers
      .sort_by { |row| row["rn"] }
      .map do |row|
        MonolithTwirp::ReposInsights::ReposInsights::V1::TopReferrer.new(
          referrer: row["referrer"],
          search_engine: row["search_engine"] || "",
          num_page_views: row["num_page_views"] || 0,
          num_unique_viewers: row["num_unique_viewers"] || 0,
        )
      end
  end
end
