# typed: true
# frozen_string_literal: true

require "test_helper"
require "notifyd-client"

class ClientSubscriptionsTest < Minitest::Test
  def setup
    TestServer.start
  end

  def teardown
    TestServer.stop
  end

  def test_client_can_request_subscriptions_from_server
    client = Notifyd::Client.new(url: Config.url, hmac_key: Config.hmac_key)
    request = Notifyd::Proto::Subscriptions::GetRequest.new(user_id: 123, filter_by_custom_fields: [])
    result = client.subscriptions.get(request)

    assert_nil(result.error)
  end

  def test_batch_create_and_delete_subscriptions_returns_deprecation_error
    client = Notifyd::Client.new(url: Config.url, hmac_key: Config.hmac_key)
    request = Notifyd::Proto::Subscriptions::BatchCreateAndDeleteRequest.new
    result = client.subscriptions.batch_create_and_delete(request)

    assert_equal :internal, result.error.code
    assert_equal "this endpoint is deprecated, use BatchReplace instead", result.error.msg
  end

  def test_returns_errors_if_user_is_invalid
    client = Notifyd::Client.new(url: Config.url, hmac_key: Config.hmac_key)
    request = Notifyd::Proto::Subscriptions::GetRequest.new(user_id: -1, filter_by_custom_fields: [])
    result = client.subscriptions.get(request)

    assert_equal :internal, result.error.code
    assert_equal "Error validating the request, please check the request contents", result.error.msg
  end
end
