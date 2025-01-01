# typed: true
# frozen_string_literal: true

require "json"
require "datadog_api_client"

class ReportAxeBase
  DatadogAPIClient.configure do |config|
    config.api_key = ENV["ACCESSIBILITY_DATADOG_API_KEY"]
  end
  DATADOG_API = DatadogAPIClient::V1::MetricsAPI.new

  def initialize(artifact_path:)
    @artifact_path = artifact_path
    @series = Hash.new { |h, k| h[k] = [] }
  end

  def submit_report!
    # Throw error if not implemented
    raise NotImplementedError
  end

  private

  def submit_metrics!(series)
    if ENV["GITHUB_EVENT_NAME"] == "schedule"
      puts "Submitting metrics to Datadog..."
      begin
        DATADOG_API.submit_metrics(DatadogAPIClient::V1::MetricsPayload.new({ series: series }))
      rescue DatadogAPIClient::APIError => e
        puts "Error when calling MetricsAPI->submit_metrics: #{e}"
      end
    else
      puts "Not submitting metrics to Datadog because this is not a scheduled run..."
    end
    series.each do |gauge|
      tag_string = gauge.tags.empty? ? "" : "[#{gauge.tags.join(', ')}]"
      puts "DOGSTATS: #{gauge.metric} #{tag_string} #{gauge.points.first[1]}|g"
    end
  end
end
