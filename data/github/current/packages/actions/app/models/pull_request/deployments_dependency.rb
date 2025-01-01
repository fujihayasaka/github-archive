# typed: false
# frozen_string_literal: true

module PullRequest::DeploymentsDependency
  extend ActiveSupport::Concern

  # Public: Notify the web socket for this pull request's "deployed" channel that the pull request was
  # successfully deployed. May affect mergeability, such as when there are required deployments.
  def notify_subscribers_of_successful_deployment
    # Omit :gid key since #global_relay_id is for the pull request header; we want the merge area that is hooked up
    # to this channel to update:
    data = {
      timestamp: Time.now.to_i,
      wait: default_live_updates_wait,
      reason: "pull request ##{id} deployment succeeded",
    }

    channel = GitHub::WebSocket::Channels.pull_request_deployed(self)
    GitHub::WebSocket.notify_pull_request_channel(self, channel, data)
  end
end
