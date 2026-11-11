# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    module Enqueue
      # Request an eventual merge of a stack. This will utilize Merge Queue if the repository utilizes that feature,
      # or falls back to AutoMerge for direct ref updates. This flows through the AutoMerge pipeline:
      #
      # Sync.call => AutoMergeRequest.create => Background Job: AutoMergeJob => Async.call => Merge, Add to Merge Queue, or wait.
      sig do
        params(
          pull_request: PullRequest,
          actor: T.any(User, Bot, Integration),
          email: T.nilable(UserEmail),
          commit_title: T.nilable(String),
          commit_message: T.nilable(String),
          remote_ip: T.nilable(String),
        ).returns(T.any(Merging::Result::Success, Merging::Result::Error, Merging::Result::NoLongerStacked))
      end
      def self.call(pull_request:, actor:, email: nil, commit_title: nil, commit_message: nil, remote_ip: nil)
        Merging::AddToAutoMerge.new(pull_request:, actor:, email:, commit_title:, commit_message:, remote_ip:).call
      end
    end
  end
end
