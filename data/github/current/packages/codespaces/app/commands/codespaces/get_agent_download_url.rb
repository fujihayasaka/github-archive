# typed: true
# frozen_string_literal: true

module Codespaces
  class GetAgentDownloadUrl < Command

    class Error < Codespaces::Error; end
    class ConnectionFailed < Codespaces::GetAgentDownloadUrl::Error; end
    class BadResponse < Codespaces::GetAgentDownloadUrl::Error; end
    class AgentDownloadUriNotFound < Codespaces::GetAgentDownloadUrl::Error; end

    def initialize(location:, vscs_target:, vscs_target_url: nil)
      @location = location
      @vscs_target = vscs_target
      @vscs_target_url = vscs_target_url
    end

    def perform
      download_info = {}
      begin
        download_info = client.fetch_agent_download_info
      rescue Codespaces::VscsClient::TimeoutError, Codespaces::VscsClient::ConnectionFailed
        raise ConnectionFailed, "Connection failed"
      rescue Codespaces::Client::BadResponseError
        raise BadResponse, "Bad response"
      end

      raise AgentDownloadUriNotFound, "Agent download uri not found" unless download_info.present? || download_info["assetUri"].present?
      download_info["assetUri"]
    end

    private

    attr_reader :vscs_target, :vscs_target_url, :location

    def client
      VscsClient.for_prebuild(
        location: location,
        vscs_target: vscs_target,
        vscs_target_url: vscs_target_url,
      )
    end
  end
end
