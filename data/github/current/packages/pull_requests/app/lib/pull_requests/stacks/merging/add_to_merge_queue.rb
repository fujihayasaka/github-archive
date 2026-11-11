# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    module Merging
      # Called from AutoMergeJob in the background. Append the requested PR and it's
      # parents to the merge queue.
      class AddToMergeQueue
        sig do
          params(
            pull_request: PullRequest,
            actor: T.any(User, Integration),
          ).void
        end
        def initialize(pull_request:, actor:)
          @pull_request = pull_request
          @actor = actor
        end

        sig { returns(T.any(Result::Success, Result::Waiting, Result::Error, Result::NoLongerStacked)) }
        def call
          return Result::NoLongerStacked.new unless @pull_request.stacked?
          return Result::NoLongerStacked.new unless stack = @pull_request.stack

          merge_queue = T.let(MergeQueue.for(repository:, branch: stack.base_ref), T.nilable(MergeQueue))
          return Result::Error.new(message: "No merge queue configured for #{stack.base_ref}") unless merge_queue

          # Resolve the triggered PR + its ancestors (position <= triggered PR's position).
          stack_entries = stack.entries
            .where("position <= ?", @pull_request.stack_position.to_i)
            .order(position: :asc)
            .includes(:pull_request)

          pull_requests = stack_entries
            .filter_map(&:pull_request)
            .reject { _1.merged? || merge_queue.has_entry_for?(pull_request: _1) }

          return Result::Success.new if pull_requests.empty?

          # Enqueue all remaining PRs in a single transactional batch
          # using the service directly to bypass the single-PR public API.
          MergeQueues::Service::Enqueue.new(repository, merge_queue.branch).call_many(
            queue: merge_queue,
            pull_requests:,
            actor: @actor
          )

          Result::Success.new
        rescue ActiveRecord::RecordInvalid => exception
          Result::Waiting.new(message: exception.record.errors.full_messages.to_sentence)
        end

        private

        sig { returns(Repository) }
        def repository = T.must(@pull_request.base_repository)
      end
    end
  end
end
