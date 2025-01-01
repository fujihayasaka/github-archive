# frozen_string_literal: true

require_relative "../authnd_server_helper"

module Authnd
  module Client
    class SocialIdentityManagerTest < Minitest::Test
      SERVER_ADDR = "127.0.0.1:18081"
      TWIRP_ADDR = "http://#{SERVER_ADDR}/twirp/".freeze
      NOT_TWIRP_URL = "http://#{SERVER_ADDR}".freeze
      UNREACHABLE_TWIRP_URL = "http://127.0.0.1:8001/twirp/"
      TEST_CATALOG_SERVICE = "github/test-service"

      @http_server = start_server(SERVER_ADDR)

      Minitest.after_run do
        stop_server
      end

      def social_identity_manager
        @social_identity_manager ||= begin
          conn = Faraday.new(url: TWIRP_ADDR) do |f|
            f.use Authnd::Client::FaradayMiddleware::HMACAuth, hmac_key: "octocat"
            f.use Authnd::Client::FaradayMiddleware::TenantContext, tenant_id: 12_345
            f.adapter(:net_http)
          end
          Authnd::Client::SocialIdentityManager.new(conn, catalog_service: TEST_CATALOG_SERVICE)
        end
      end

      def test_find_social_identity_with_missing_user_email_id
        ex = assert_raises ArgumentError do
          social_identity_manager.find_social_identity(
            0,
            "1234",
            nil, # missing user_email_id
          )
        end
        assert_equal "user_email_id must be an integer", ex.message
      end
    end
  end
end
