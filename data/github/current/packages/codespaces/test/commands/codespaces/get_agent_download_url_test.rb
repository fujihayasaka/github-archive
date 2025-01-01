# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class GetAgentDownloadUrlTest < GitHub::TestCase
    include CodespacesPlanFixtures

    context ".perform" do
      test "returns the download url for the agent" do
        location = "WestUs2"
        vscs_target = Codespaces::Vscs.default_target

        url = Codespaces::GetAgentDownloadUrl.call(location: location, vscs_target: vscs_target)
        assert_equal url, "https://agent-sas-url"
      end

      test "raises an exception if vscs does not respond with a proper url" do
        Codespaces::VscsClient.any_instance.stubs(:fetch_agent_download_info).returns({})

        location = "WestUs2"
        vscs_target = Codespaces::Vscs.default_target

        assert_raises Codespaces::GetAgentDownloadUrl::AgentDownloadUriNotFound do
          Codespaces::GetAgentDownloadUrl.call(location: location, vscs_target: vscs_target)
        end
      end

      test "raises an exception if vscs connection times out" do
        Codespaces::VscsClient.any_instance.stubs(:fetch_agent_download_info).raises(Codespaces::VscsClient::TimeoutError)

        location = "WestUs2"
        vscs_target = Codespaces::Vscs.default_target

        assert_raises Codespaces::GetAgentDownloadUrl::ConnectionFailed do
          Codespaces::GetAgentDownloadUrl.call(location: location, vscs_target: vscs_target)
        end
      end

      test "raises an exception if vscs connection fail" do
        Codespaces::VscsClient.any_instance.stubs(:fetch_agent_download_info).raises(Codespaces::VscsClient::ConnectionFailed)

        location = "WestUs2"
        vscs_target = Codespaces::Vscs.default_target

        assert_raises Codespaces::GetAgentDownloadUrl::ConnectionFailed do
          Codespaces::GetAgentDownloadUrl.call(location: location, vscs_target: vscs_target)
        end
      end

      test "raises an exception if vscs returns a bad response" do
        Codespaces::VscsClient.any_instance.stubs(:fetch_agent_download_info).raises(Codespaces::Client::BadResponseError.new("BOOM!"))

        location = "WestUs2"
        vscs_target = Codespaces::Vscs.default_target

        assert_raises Codespaces::GetAgentDownloadUrl::BadResponse do
          Codespaces::GetAgentDownloadUrl.call(location: location, vscs_target: vscs_target)
        end
      end
    end
  end
end
