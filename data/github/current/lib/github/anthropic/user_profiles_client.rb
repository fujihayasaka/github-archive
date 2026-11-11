# typed: true
# frozen_string_literal: true

require "cgi"

module GitHub
  module Anthropic
    class UserProfilesClient
      def initialize(connection: nil)
        @connection = connection || build_connection
      end

      def get_user_profile(user_profile_id)
        @connection.get("/v1/user_profiles/#{CGI.escape(user_profile_id)}")
      end

      def create_user_profile(name:, external_id:)
        @connection.post("/v1/user_profiles", { name: name, external_id: external_id })
      end

      private

      def build_connection
        ::GitHub::FaradayClient::External.new(GitHub.anthropic_api_url) do |conn|
          conn.headers["x-api-key"] = api_key
          conn.headers["anthropic-version"] = "2023-06-01"
          conn.headers["anthropic-beta"] = "user-profiles-2026-03-24"
          conn.request :json
          conn.response :json
          conn.options[:timeout] = 60_000
          conn.adapter Faraday.default_adapter
        end
      end

      def api_key
        GitHub.copilot_anthropic_user_profiles_secret
      end
    end
  end
end
