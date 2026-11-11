# frozen_string_literal: true

module Activity
  module PullRequestEvents
    CREATED = "created"
    REOPENED = "reopened"
    MERGED = "merged"
    CLOSED = "closed"
    COMMENT = "comment"
    APPROVED = "approved"
  end

  class PullRequestLogger < Activity::Logger
    attr_reader :pull_request

    def initialize(pull_request:, context_name: "pull_request")
      @pull_request = pull_request

      super(
        context_name: context_name,
        context: context_from_pull_request.merge(pull_request.telemetry_attributes)
      )
    end

    def context_from_pull_request
      context_from_update_config.merge(
        {
          pull_request_github_number: pull_request.github_number,
          pull_request_head_commit_sha: pull_request.head_commit_sha,
          pull_request_dependabot_commit_sha: pull_request.dependabot_commit_sha,
          pull_request_base_commit_sha: pull_request.base_commit_sha,
          pull_request_state: pull_request.current_state,
          pull_request_github_url: pull_request.github_url,
        }
      )
    end

    private

    def context_from_update_config
      Activity::UpdateConfigLogger.new(update_config: @pull_request.update_config).context_from_update_config
    end
  end
end
