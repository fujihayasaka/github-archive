# typed: true
# frozen_string_literal: true

class CollectMetricsJob < ApplicationJob
  DEFAULT_LOCK_KEY = "collect_instance_metrics"
  PERIODS = %w[week month year]
  QUERIES = %w[
    issues_created
    issues_closed
    commits_contributed
    pull_request_reviews_created
    pull_requests_created
    pull_requests_merged
  ]
  INSTANCE_ONLY_QUERIES = %w[
    issue_comments_created
    organizations_created
    repositories_created
    teams_created
    users_created
  ]

  queue_as :collect_metrics
  locked_by timeout: 1.hour, key: ->(_job) { DEFAULT_LOCK_KEY }
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(**query_params)
    return unless GitHub.enterprise?

    queries(query_params).product(PERIODS, [query_params]).
      map(&method(:build_query)).
      each(&method(:run_and_cache_query))
  end

  private

  def queries(query_params)
    QUERIES.concat(INSTANCE_ONLY_QUERIES)
  end

  def build_query((name, period, query_params))
    MetricQuery.build name,
      **query_params,
      timespan: MetricTimespan.for(period).new
  end

  def run_and_cache_query(query)
    query.cache_put
    query.previous.cache_put
  end
end
