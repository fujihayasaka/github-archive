# typed: true
# frozen_string_literal: true

require "test_helper"
require "notifyd-client"

class ClientIntegrationTest < Minitest::Test
  def setup
    TestServer.start
  end

  def teardown
    TestServer.stop
  end

  def test_client_can_request_from_server
    client = Notifyd::Client.new(url: Config.url, hmac_key: Config.hmac_key)
    request = Notifyd::Proto::DeviceTokensV2::SetRequest.new(user_id: 123, oauth_access_id: 456, token: "abc123")
    result = client.device_tokens_v2.set(request)

    assert_nil(result.error)
  end

  def test_client_cannot_request_from_server_with_bad_hmac_key
    client = Notifyd::Client.new(url: Config.url, hmac_key: "meh")

    request = Notifyd::Proto::DeviceTokensV2::SetRequest.new(user_id: 123, oauth_access_id: 456, token: "abc123")
    result = client.device_tokens_v2.set(request)

    refute_nil(result.error)
    assert_equal(:unauthenticated, result.error.code)
  end
end
