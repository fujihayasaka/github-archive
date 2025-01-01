# typed: strict
# frozen_string_literal: true

require "datadog_api_client"

module BrowserStats
  class DevReporter

    sig { params(stats: T::Hash[String, T.untyped]).void }
    def initialize(stats)
      return if ENV["DX_TELEMETRY_DATADOG_API_KEY"].nil?

      DatadogAPIClient.configure do |config|
        config.api_key = ENV["DX_TELEMETRY_DATADOG_API_KEY"]
      end

      @client = T.let(DatadogAPIClient::V1::MetricsAPI.new, T.nilable(DatadogAPIClient::V1::MetricsAPI))
      @stats = T.let(stats["stats"], T::Array[T::Hash[String, T.untyped]])
    end

    sig { void }
    def report
      return if @client.nil?

      stat = @stats.find { |stat| stat.has_key?("navigationTimings") }

      return if stat.nil?

      stat = stat.try(:deep_transform_keys, &:underscore)
      stat = parse_navigation_resource_timing(stat["navigation_timings"])

      return if stat.nil?

      report_metrics(stat)
    end

    private

    sig { params(navigation_timings: T::Array[T::Hash[String, T.untyped]]).void }
    def report_metrics(navigation_timings)
      navigation_timings.each do |timing|
        tags = ["bundler:#{bundler}", "cpu:#{Etc.nprocessors}"]

        if request_url = timing["name"]
          if match = guess_url_controller_action(request_url.to_s)
            tags << "controller:#{match[0]}"
            tags << "action:#{match[1]}"
          end
        end

        report_timing_range("monolith.browser.dist.domcomplete", timing, "dom_content_loaded_event_end", "dom_complete", tags: tags)
        report_timing_range("monolith.browser.dist.domcontentloaded", timing, "dom_content_loaded_event_start", "dom_content_loaded_event_end", tags: tags)
        report_timing_range("monolith.browser.dist.dominteractive", timing, "response_end", "dom_interactive", tags: tags)
      end
    end

    sig { params(name: String, timing: T::Hash[String, Integer], start_key: String, end_key: String, tags: T::Array[String]).void }
    def report_timing_range(name, timing, start_key, end_key, tags:)
      return unless timing[end_key] && timing[start_key]

      ms = T.must(timing[end_key]) - T.must(timing[start_key])
      return unless ms > 0
      return if ms > 1.year * 1000

      body = DatadogAPIClient::V1::DistributionPointsPayload.new({
        series: [
          DatadogAPIClient::V1::DistributionPointsSeries.new({
            metric: name,
            points: [[Time.now.to_i, [ms]]],
            tags: tags,
          }),
        ],
      })

      @client&.submit_distribution_points(body)
    end

    sig { params(navigation_timings: T::Hash[String, T.untyped]).returns(T.nilable(T::Array[T::Hash[String, T.untyped]])) }
    def parse_navigation_resource_timing(navigation_timings)
      navigation_timings.try(:map) do |navigation_or_resource_timing|
        navigation_or_resource_timing["name"] = URI.parse(navigation_or_resource_timing["name"])
        navigation_or_resource_timing.transform_keys(&:underscore)
      end
    rescue URI::InvalidURIError
      nil
    end

    sig { params(url: String).returns(T.nilable(T::Array[T.any(Symbol, String)])) }
    def guess_url_controller_action(url)
      if params = guess_url_params(url)
        controller = GitHub::TaggingHelper.formatted_controller(params[:controller])
        [controller, params[:action]]
      end
    end

    sig { params(url: String).returns(T.nilable(T::Hash[Symbol, String])) }
    def guess_url_params(url)
      parsed_url = Addressable::URI.parse(url).to_s
      if parsed_url.present?
        T.unsafe(GitHub::Application).routes.recognize_path(parsed_url, method: :get)
      end
    rescue ActionController::RoutingError, Addressable::URI::InvalidURIError
      nil
    end

    sig { returns(String) }
    def bundler
      if GitHub.webpack_dev_server_enabled?
        "webpack"
      elsif GitHub.vite_dev_server_enabled?
        "vite"
      else
        "unknown"
      end
    end
  end
end
