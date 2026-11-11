# typed: strict
# frozen_string_literal: true

module PullRequests
  module AsyncMerge

    sig do
      params(
        pull_request: PullRequest,
        repository: Repository,
        actor: User,
        mode: Symbol,
        merge_method: Symbol,
        commit_title: T.nilable(String),
        commit_message: T.nilable(String),
        commit_email_address: T.nilable(UserEmail),
        actor_ip_address: T.nilable(String)
      ).returns(T.any(
        PullRequests::Merge::Results::Created,
        PullRequests::Merge::Results::Error,
        PullRequests::Merge::Results::AlreadyEnqueued,
        PullRequests::Merge::Results::AlreadyMerged,
        PullRequests::Merge::Results::Invalid
      ))
    end
    def self.call(
      pull_request:,
      repository:,
      actor:,
      mode:,
      merge_method:,
      commit_title:,
      commit_message:,
      commit_email_address:,
      actor_ip_address:
    )
      strategy = case merge_method
      when :squash
        PullRequests::Merge::Enums::Strategy::Squash
      when :merge
        PullRequests::Merge::Enums::Strategy::Merge
      when :rebase
        PullRequests::Merge::Enums::Strategy::Rebase
      else
        PullRequests::Merge::Enums::Strategy::Merge
      end

      resolved_mode = case mode
      when :queue
        PullRequests::Merge::Mode::Queue.new(
          jump: merge_method == :jump,
          solo: merge_method == :solo,
        )
      when :now
        PullRequests::Merge::Mode::Now.new(strategy: strategy)
      when :wait
        PullRequests::Merge::Mode::Wait.new(strategy: strategy)
      else
        PullRequests::Merge::Mode::Wait.new(strategy: strategy)
      end

      PullRequests::Merge::Creation::Service.new(
        pull_request:,
        repository:,
        actor:,
        mode: resolved_mode,
        commit_title:,
        commit_message:,
        commit_email_address:,
        actor_ip_address:,
      ).call
    end
  end
end
