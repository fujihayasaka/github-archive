# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  module Public

    sig { returns(Dials::CopilotLogsPollingIntervalSeconds) }
    def self.copilot_logs_polling_interval_seconds
      Dials::CopilotLogsPollingIntervalSeconds.new(force_cache_miss: true)
    end

    sig { returns(Dials::CopilotSessionsPollingIntervalSeconds) }
    def self.copilot_sessions_polling_interval_seconds
      Dials::CopilotSessionsPollingIntervalSeconds.new(force_cache_miss: true)
    end

    sig { params(pull_request_ids: T::Array[Integer], user: User).returns(T::Hash[Integer, Payloads::Pull::PullHash]) }
    def self.id_to_pull_request_map(pull_request_ids:, user:)
      prs = PullRequest.includes(:repository).where(id: pull_request_ids).limit(100).index_by(&:id)
      prs.reject! do |_pr_id, pr|
        repo = pr.repository
        next true if repo.nil? # Reject if the repo has been deleted

        # Reject if the user is spammy and it's determined they shouldn't
        # see the PR or if they don't have read access to the repo
        pr.hide_from_user?(user) || !repo.readable_by?(user)
      end

      # Group sessions by pull request using Rails grouping
      id_to_pull_request_map = prs.map do |pr_id, pr|
        [pr_id, Payloads::Pull.new(pull_request: pr).call]
      end.to_h
    end

    sig { params(user: User).returns(T::Boolean) }
    def self.show_copilot_coding_agent_premium_requests_banner(user)
      return false unless FeatureFlag.vexi.enabled?("copilot_swe_agent_initiator_agent", user, default: false)
      notice_dismissed = user.dismissed_notice?("copilot_coding_agent_premium_requests_banner")
      !(notice_dismissed || notice_dismissed.nil?)
    end

    sig { params(user: User).returns(T::Boolean) }
    def self.show_copilot_coding_agent_entry_point_popover?(user)
      return false unless FeatureFlag.vexi.enabled?("copilot_global_agent_button", user, default: false)
      return false unless FeatureFlag.vexi.enabled?("copilot_global_agent_button_popover", user, default: false)
      return true if FeatureFlag.vexi.enabled?("copilot_global_agent_button_popover_ignore_dismiss", user, default: false)
      notice_dismissed = user.dismissed_notice?("copilot_coding_agent_entry_point_popover")
      !(notice_dismissed || notice_dismissed.nil?)
    end
  end
end
