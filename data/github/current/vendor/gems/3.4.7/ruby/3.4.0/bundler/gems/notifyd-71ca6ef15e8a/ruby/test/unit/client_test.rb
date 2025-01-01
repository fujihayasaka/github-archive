# typed: true
# frozen_string_literal: true

require "test_helper"
require "notifyd-client"

class ClientTest < Minitest::Test
  include TypedMocks

  def test_subscriptions_client
    client = Notifyd::Client.new(url: Config.url, hmac_key: Config.hmac_key)

    assert_kind_of Notifyd::Proto::Subscriptions::SubscriptionsClient, client.subscriptions
  end

  def test_routing_settings_client
    client = Notifyd::Client.new(url: Config.url, hmac_key: Config.hmac_key)

    assert_kind_of Notifyd::Proto::RoutingSettings::RoutingSettingsClient, client.routing_settings
  end

  def test_newsies_client
    client = Notifyd::Client.new(url: Config.url, hmac_key: Config.hmac_key)

    assert_kind_of Notifyd::Proto::Newsies::NewsiesClient, client.newsies
  end

  def test_checking_predicate_methods_dont_raise_errors
    client = Notifyd::Client.new(url: Config.url, hmac_key: Config.hmac_key)

    refute_respond_to client, :empty?
    refute_respond_to client, :test!
  end

  def test_retries_if_timeout
    retries = -1
    req_stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/twirp/notifyd.api.subscriptions_v2.Subscriptions/Get") do
        retries += 1
        raise Faraday::TimeoutError
      end
    end

    mockable(Faraday).stubs(:default_adapter).returns([:test, req_stubs])
    client = Notifyd::Client.new(url: Config.url, hmac_key: Config.hmac_key) do |build|
      build.use_retry
    end

    assert_raises Faraday::TimeoutError do
      client.subscriptions.get(Notifyd::Proto::Subscriptions::GetRequest.new({user_id: 1}))
    end

    assert_equal 2, retries
  end

  def test_does_not_retry_if_success
    retries = -1
    req_stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/twirp/notifyd.api.devicetokens_v2.DeviceTokensV2/DeleteAll") do
        retries += 1
        [200, {}, { message: "test OK" }.to_json]
      end
    end

    mockable(Faraday).stubs(:default_adapter).returns([:test, req_stubs])
    client = Notifyd::Client.new(url: Config.url, hmac_key: Config.hmac_key) do |build|
      build.use_retry
    end

    client.device_tokens_v2.delete_all(Notifyd::Proto::DeviceTokensV2::DeleteAllRequest.new({user_id: 1}))

    assert_equal 0, retries
  end

  def test_can_set_a_custom_adapter
    called = 0
    req_stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/twirp/notifyd.api.devicetokens_v2.DeviceTokensV2/DeleteAll") do
        called += 1
        [200, {}, { message: "test OK" }.to_json]
      end
    end

    client = Notifyd::Client.new(url: Config.url, hmac_key: Config.hmac_key) do |build|
      build.use_adapter :test, req_stubs
    end

    client.device_tokens_v2.delete_all(Notifyd::Proto::DeviceTokensV2::DeleteAllRequest.new({user_id: 1}))

    assert_equal 1, called
  end
end
