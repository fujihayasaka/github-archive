# typed: true
# frozen_string_literal: true

require "hydro_aggregation_api/v1/api_pb"
require "hydro_aggregation_api/v1/api_twirp"

module HydroAggregationApi
  class Client
    PAGE_VIEWS_DATA_SOURCE = "RepoTraffic"
    CLONES_DATA_SOURCE = "RepoClones"

    def self.build(url:, timeout: 3, &block)
      circuit_breaker ||= default_circuit_breaker
      connection = build_http_client(url, timeout, &block)
      new(HydroAggregationApi::V1::AggregationServiceClient.new(connection))
    end

    def self.default_circuit_breaker
      Resilient::CircuitBreaker.get("hydro_aggregation_api", {
        sleep_window_seconds: 30,
        request_volume_threshold: 3,
        error_threshold_percentage: 50,
      })
    end

    def self.build_http_client(url, timeout)
      Faraday.new(url) do |conn|
        conn.options.timeout = timeout
        if block_given?
          # block must specify an adapter!
          yield conn
        else
          conn.adapter Faraday.default_adapter
        end
      end
    end

    def initialize(twirp_client, circuit_breaker: nil)
      @twirp_client = twirp_client
      @circuit_breaker = circuit_breaker || self.class.default_circuit_breaker
    end

    def repo_top_content(repo_id:, from:)
      top_n_query(
        query_id: :repo_top_content,
        data_source: PAGE_VIEWS_DATA_SOURCE,
        dimension: "page_and_title",
        metric: "views",
        limit: 10,
        filter: {
          repository_id: repo_id.to_s,
        },
        aggregations: [
          {
            name: "views",
            type: :SUM,
          },
          {
            name: "visitors",
            type: :DISTINCT_COUNT,
          }
        ],
        from: from&.utc,
        noop: true,
      )
    end

    def repo_top_referrers(repo_id:, from:)
      top_n_query(
        query_id: :repo_top_referrers,
        data_source: PAGE_VIEWS_DATA_SOURCE,
        dimension: "referrer_domain",
        metric: "views",
        limit: 10,
        filter: {
          repository_id: repo_id.to_s,
        },
        aggregations: [
          {
            name: "views",
            type: :SUM,
          },
          {
            name: "visitors",
            type: :DISTINCT_COUNT,
          }
        ],
        from: from&.utc,
        noop: true,
      )
    end

    def repo_page_views(repo_id:, from:, granularity: :DAY)
      timeseries_query(
        query_id: :repo_page_views,
        data_source: PAGE_VIEWS_DATA_SOURCE,
        granularity: granularity,
        filter: {
          repository_id: repo_id.to_s,
        },
        aggregations: [
          {
            name: "views",
            type: :SUM,
          },
          {
            name: "visitors",
            type: :DISTINCT_COUNT,
          }
        ],
        from: from&.utc,
        noop: true,
      )
    end

    def repo_clones(repo_id:, from:, granularity: :DAY)
      timeseries_query(
        query_id: :repo_clones,
        data_source: CLONES_DATA_SOURCE,
        granularity: granularity,
        filter: {
          repository_id: repo_id.to_s,
        },
        aggregations: [
          {
            name: "clones",
            type: :SUM,
          },
        ],
        from: from&.utc,
        noop: true,
      )
    end

    private

    attr_reader :circuit_breaker

    def top_n_query(params)
      return unless GitHub.hydro_aggregation_api_enabled?
      query_type = :top_n

      report_latency(query_id: params[:query_id], query_type: query_type) do
        response = @twirp_client.top_n(HydroAggregationApi::V1::TopNRequest.new(params))

        if response.error
          report_failure(query_id: params[:query_id], query_type: query_type, error: response.error.code)
        end

        nil # Discard query results for now
      end
    end

    def timeseries_query(params)
      return unless GitHub.hydro_aggregation_api_enabled?
      query_type = :timeseries

      report_latency(query_id: params[:query_id], query_type: query_type) do
        response = @twirp_client.timeseries(HydroAggregationApi::V1::TimeseriesRequest.new(params))

        if response.error
          report_failure(query_id: params[:query_id], query_type: query_type, error: response.error.code)
        end

        nil # Discard query results for now
      end
    end

    def report_latency(query_id:, query_type:)
      return unless circuit_breaker.allow_request?

      GitHub.dogstats.distribution_time("hydro_agg.query", tags: ["query_id:#{query_id}", "type:#{query_type}"]) do
        begin
          yield.tap do
            circuit_breaker.success
          end
        rescue => e # rubocop:todo Lint/GenericRescue
          circuit_breaker.failure
          report_failure(query_id: query_id, query_type: query_type, error: e.class.name)
          Failbot.report(e)
        end
      end
    end

    def report_failure(query_id:, query_type:, error:)
      GitHub.dogstats.increment("hydro_agg.error", tags: ["query_id:#{query_id}", "type:#{query_type}", "error:#{error}"])
    end
  end
end
