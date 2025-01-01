# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class DeviceTokensServiceTest < GitHub::TestCase
    include NotifydTestHelper

    setup do
      @notifyd_client_mock = mock("Notifyd::Client")
      Notifyd.stubs(:client).returns(@notifyd_client_mock)
      @device_tokens_client_mock = mock("Notifyd::Proto::DeviceTokensV2::DeviceTokensV2Client")
        .responds_like_instance_of(Notifyd::Proto::DeviceTokensV2::DeviceTokensV2Client)
      @notifyd_client_mock.stubs(:device_tokens_v2).returns(@device_tokens_client_mock)
    end

    context "set", skip_enterprise: true do
      test "success" do
        user_id = 42
        oauth_access_id = 23
        token = "a token"

        request = Notifyd::Proto::DeviceTokensV2::SetRequest.new(user_id:, oauth_access_id:, token:)
        @device_tokens_client_mock.expects(:set).with(request).returns(Twirp::ClientResp.new(data: Google::Protobuf::BoolValue.new(value: true)))

        assert Notifyd::DeviceTokensService.set(user_id:, oauth_access_id:, token:)
      end

      test "success but not set" do
        user_id = 42
        oauth_access_id = 23
        token = "a token"

        request = Notifyd::Proto::DeviceTokensV2::SetRequest.new(user_id:, oauth_access_id:, token:)
        @device_tokens_client_mock.expects(:set).with(request).returns(Twirp::ClientResp.new(data: Google::Protobuf::BoolValue.new(value: false)))

        assert_equal false, Notifyd::DeviceTokensService.set(user_id:, oauth_access_id:, token:)
      end

      test "error" do
        user_id = 42
        oauth_access_id = 23
        token = "a token"

        request = Notifyd::Proto::DeviceTokensV2::SetRequest.new(user_id:, oauth_access_id:, token:)
        @device_tokens_client_mock.expects(:set).with(request).returns(Twirp::ClientResp.new(error: Twirp::Error.unavailable("unavailable")))

        assert_nil Notifyd::DeviceTokensService.set(user_id:, oauth_access_id:, token:)
      end
    end

    context "delete", skip_enterprise: true do
      test "success" do
        user_id = 42
        token = "a token"

        request = Notifyd::Proto::DeviceTokensV2::DeleteRequest.new(user_id:, token:)
        @device_tokens_client_mock.expects(:delete).with(request).returns(Twirp::ClientResp.new)

        assert Notifyd::DeviceTokensService.delete(user_id:, token:)
      end

      test "error" do
        user_id = 42
        token = "a token"

        request = Notifyd::Proto::DeviceTokensV2::DeleteRequest.new(user_id:, token:)
        @device_tokens_client_mock.expects(:delete).with(request).returns(Twirp::ClientResp.new(error: Twirp::Error.unavailable("unavailable")))

        refute Notifyd::DeviceTokensService.delete(user_id:, token:)
      end
    end

    context "delete_all", skip_enterprise: true do
      test "success" do
        user_id = 42

        request = Notifyd::Proto::DeviceTokensV2::DeleteAllRequest.new(user_id:)
        @device_tokens_client_mock.expects(:delete_all).with(request).returns(Twirp::ClientResp.new)

        assert Notifyd::DeviceTokensService.delete_all(user_id:)
      end

      test "error" do
        user_id = 42

        request = Notifyd::Proto::DeviceTokensV2::DeleteAllRequest.new(user_id:)
        @device_tokens_client_mock.expects(:delete_all).with(request).returns(Twirp::ClientResp.new(error: Twirp::Error.unavailable("unavailable")))

        refute Notifyd::DeviceTokensService.delete_all(user_id:)
      end
    end
  end
end
