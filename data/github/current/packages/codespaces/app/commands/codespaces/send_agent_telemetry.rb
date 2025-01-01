# typed: true
# frozen_string_literal: true

module Codespaces
  class SendAgentTelemetry < Command

    class Error < Codespaces::Error; end
    class ConnectionFailed < Codespaces::SendAgentTelemetry::Error; end
    class BadResponse < Codespaces::SendAgentTelemetry::Error; end

    def initialize(telemetry_json:, location:, vscs_target:, vscs_target_url: nil)
      @telemetry_json = telemetry_json
      @location = location
      @vscs_target = vscs_target
      @vscs_target_url = vscs_target_url
    end

    def perform
      begin
        client.send_agent_telemetry telemetry_json
      rescue Codespaces::VscsClient::TimeoutError, Codespaces::VscsClient::ConnectionFailed
        raise ConnectionFailed, "Connection failed"
      rescue Codespaces::Client::BadResponseError
        raise BadResponse, "Bad response"
      end
    end

    private

    attr_reader :vscs_target, :vscs_target_url, :location, :telemetry_json

    def client
      VscsClient.for_prebuild(
        location: location,
        vscs_target: vscs_target,
        vscs_target_url: vscs_target_url,
      )
    end
  end
end
