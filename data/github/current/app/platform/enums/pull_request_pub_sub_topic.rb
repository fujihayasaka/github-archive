# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestPubSubTopic < Platform::Enums::Base
      description "The possible PubSub channels for a pull request."
      mobile_only true
      required_capabilities [:subscribe_alive_events]

      value "UPDATED", "The channel ID for observing pull request updates.", value: "updated"
      value "HEAD_REF", "The channel ID for observing head ref updates.", value: "head_ref"
      value "BASE_REF", "The channel ID for observing base ref updates.", value: "base_ref"
      value "COMMIT_HEAD_SHA", "The channel ID for observing head commit updates.", value: "commit_head_sha"
      value "TIMELINE", "The channel ID for updating items on the pull request timeline.", value: "timeline"
      value "STATE", "The channel ID for observing pull request state updates.", value: "state"
      value "DEPLOYED", "The channel ID for observing pull request deployed updates.", value: "deployed"
      value "REVIEW_STATE", "The channel ID for observing pull request review state updates.", value: "review_state"
      value "MERGEABILITY", "The channel ID for observing pull request mergeability with HEAD or base branch.", value: "mergeability"
      value "WORKFLOWS", "The channel ID for observing pull request workflow run updates.", value: "workflows"
      value "MERGE_QUEUE", "The channel ID for observing pull request merge queue entry updates.", value: "merge_queue"
      value "GIT_MERGE_STATE", "The channel ID for observing pull request git merge state updates.", value: "git_merge_state"
      value "PRESENCE", "The channel ID for observing pull request user presence updates.", value: "presence"
    end
  end
end
