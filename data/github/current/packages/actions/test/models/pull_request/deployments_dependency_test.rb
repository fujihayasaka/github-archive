# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestDeploymentsDependencyTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, from_example: :simple)

    @pull_request = create(:pull_request, repository: @repo, base_ref: "master", head_ref: "cr-line-endings")
  end

  context "#notify_subscribers_of_successful_deployment" do
    test "notifies the right pull request channel" do
      expected_channel = GitHub::WebSocket::Channels.pull_request_deployed(@pull_request)

      freeze_time do
        GitHub::WebSocket.expects(:notify_pull_request_channel).once.with(@pull_request, expected_channel, equals(
          timestamp: Time.now.to_i,
          wait: @pull_request.default_live_updates_wait,
          reason: "pull request ##{@pull_request.id} deployment succeeded",
        ))

        @pull_request.notify_subscribers_of_successful_deployment
      end
    end
  end
end
