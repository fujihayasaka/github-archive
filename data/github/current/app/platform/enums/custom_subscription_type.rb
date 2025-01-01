# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CustomSubscriptionType < Platform::Enums::Base
      description "The possible custom types to subscribe to"
      mobile_only true

      value "DISCUSSION", "Subscribe to a repository's discussions.", value: "Discussion"
      value "ISSUE", "Subscribe to a repository's issues.", value: "Issue"
      value "RELEASE", "Subscribe to a repository's releases.", value: "Release"
      value "PULL_REQUEST", "Subscribe to a repository's pull requests.", value: "PullRequest"
      value "SECURITY_ALERT", "Subscribe to a repository's security alerts.", value: "SecurityAlert"

    end
  end
end
