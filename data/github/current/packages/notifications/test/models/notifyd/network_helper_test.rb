# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class NetworkHelperTest < GitHub::TestCase

    include NetworkHelper
    include DogstatsTestHelpers

    test "returns and logs success" do
      response = make_network_request_to_notifyd("class_name", false, ["tag"]) do
        Twirp::ClientResp.new(data: "test")
      end

      assert_equal response.data, "test"
      assert_dogstats_increment 1, "notifications.notifyd_request", tags: ["request:class_name", "success:true", "tag"]

    end

    context "failures" do
      context "raise error is false" do
        test "does not raise non-unavailable Twirp errors and logs failure" do
          NotifydFailbot.expects(:report).once
          response = make_network_request_to_notifyd("class_name", false, ["tag"]) do
            Twirp::ClientResp.new(data: nil, error: Twirp::Error.invalid_argument("invalid"))
          end
          assert_nil response
          assert_dogstats_increment 1, "notifications.notifyd_request", tags: ["request:class_name", "success:false", "error:invalid_argument", "tag"]
        end

        test "does not raise unavailable Twirp errors and logs failure" do
          NotifydFailbot.expects(:report).never
          response = make_network_request_to_notifyd("class_name", false, ["tag"]) do
            Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable"))
          end
          assert_nil response
          assert_dogstats_increment 1, "notifications.notifyd_request", tags: ["request:class_name", "success:false", "error:unavailable", "tag"]

        end

        test "does not raise Faraday::ConnectionFailed errors and logs failure" do
          NotifydFailbot.expects(:report).never
          response = make_network_request_to_notifyd("class_name", false, ["tag"]) do
            raise Faraday::ConnectionFailed.new("boom!")
          end
          assert_nil response
          assert_dogstats_increment 1, "notifications.notifyd_request", tags: ["request:class_name", "success:false", "error:connection", "tag"]

        end

        test "does not raise Faraday::TimeoutError errors and logs failure" do
          NotifydFailbot.expects(:report).never
          response = make_network_request_to_notifyd("class_name", false, ["tag"]) do
            raise Faraday::TimeoutError.new("boom!")
          end
          assert_nil response
          assert_dogstats_increment 1, "notifications.notifyd_request", tags: ["request:class_name", "success:false", "error:connection", "tag"]

        end

      end

      context "raise error is true" do
        test "raises non-unavailable Twirp errors as ResponseError and logs failure" do
          NotifydFailbot.expects(:report).once
          assert_raises ResponseError do
            make_network_request_to_notifyd("class_name", true, ["tag"]) do
              Twirp::ClientResp.new(data: nil, error: Twirp::Error.invalid_argument("invalid"))
            end
          end
          assert_dogstats_increment 1, "notifications.notifyd_request", tags: ["request:class_name", "success:false", "error:invalid_argument", "tag"]
        end

        test "raises unavailable Twirp errors as ConnectionError and logs failure" do
          NotifydFailbot.expects(:report).never
          assert_raises ConnectionError do
            make_network_request_to_notifyd("class_name", true, ["tag"]) do
              Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable"))
            end
          end
          assert_dogstats_increment 1, "notifications.notifyd_request", tags: ["request:class_name", "success:false", "error:unavailable", "tag"]
        end

        test "raises Faraday::ConnectionFailed errors as ConnectionError and logs failure" do
          NotifydFailbot.expects(:report).never
          assert_raises ConnectionError do
            make_network_request_to_notifyd("class_name", true, ["tag"]) do
              raise Faraday::ConnectionFailed.new("boom!")
            end
          end
          assert_dogstats_increment 1, "notifications.notifyd_request", tags: ["request:class_name", "success:false", "error:connection", "tag"]
        end

        test "raises Faraday::TimeoutError errors as ConnectionError and logs failure" do
          NotifydFailbot.expects(:report).never
          assert_raises ConnectionError do
            make_network_request_to_notifyd("class_name", true, ["tag"]) do
              raise Faraday::TimeoutError.new("boom!")
            end
          end
          assert_dogstats_increment 1, "notifications.notifyd_request", tags: ["request:class_name", "success:false", "error:connection", "tag"]
        end
      end
    end
  end
end
