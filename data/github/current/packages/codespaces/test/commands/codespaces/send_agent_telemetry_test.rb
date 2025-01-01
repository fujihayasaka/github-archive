# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class SendAgentTelemetryTest < GitHub::TestCase
    include CodespacesPlanFixtures

    context ".perform" do
      test "send agent telemetry json" do
        location = "WestUs2"
        vscs_target = Codespaces::Vscs.default_target
        telemetry_data = [
          {
            Level: "info",
            Time: "timestring",
            Message: "info_msg_str",
            OptionalValues: {
                SomeKey: "Value1",
            },
          },
          {
            Level: "error",
            Time: "timestring",
            Message: "error_msg",
            OptionalValues: {
              SomeKey: "Value2",
            },
          }
        ]

        Codespaces::VscsClient.any_instance.expects(:send_agent_telemetry).with(telemetry_data.to_json).once
        Codespaces::SendAgentTelemetry.call(telemetry_json: telemetry_data.to_json, location: location, vscs_target: vscs_target)
      end

      test "raises an exception if vscs connection times out" do
        Codespaces::VscsClient.any_instance.stubs(:send_agent_telemetry).raises(Codespaces::VscsClient::TimeoutError)

        location = "WestUs2"
        vscs_target = Codespaces::Vscs.default_target

        assert_raises Codespaces::SendAgentTelemetry::ConnectionFailed do
          Codespaces::SendAgentTelemetry.call(telemetry_json: [].to_json, location: location, vscs_target: vscs_target)
        end
      end

      test "raises an exception if vscs connection fail" do
        Codespaces::VscsClient.any_instance.stubs(:send_agent_telemetry).raises(Codespaces::VscsClient::ConnectionFailed)

        location = "WestUs2"
        vscs_target = Codespaces::Vscs.default_target

        assert_raises Codespaces::SendAgentTelemetry::ConnectionFailed do
          Codespaces::SendAgentTelemetry.call(telemetry_json: [].to_json, location: location, vscs_target: vscs_target)
        end
      end

      test "raises an exception if vscs returns a bad response" do
        Codespaces::VscsClient.any_instance.stubs(:send_agent_telemetry).raises(Codespaces::Client::BadResponseError.new("BOOM!"))

        location = "WestUs2"
        vscs_target = Codespaces::Vscs.default_target

        assert_raises Codespaces::SendAgentTelemetry::BadResponse do
          Codespaces::SendAgentTelemetry.call(telemetry_json: [].to_json, location: location, vscs_target: vscs_target)
        end
      end
    end
  end
end
