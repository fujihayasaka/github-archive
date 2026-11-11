# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    class UpdateAllBranchesJob < ApplicationJob
      include GitHub::Memoizer

      queue_as :pull_requests_stacks_update_all_branches

      use_primaries ApplicationRecord::IssuesPullRequests

      retry_on_dirty_exit

      sig do
        params(
          start_pull_request: ::PullRequest,
          actor: ::User,
          expected_head_oid_by_pr_number: T::Hash[String, String],
        ).void
      end
      def perform(start_pull_request:, actor:, expected_head_oid_by_pr_number:)
        return unless start_pull_request.stacked?

        Stacks.lock!(stack, ttl: 2.minutes) do
          pulls = stack.pulls_from(start_pull_request)

          begin
            base_oid = repository.heads.find(start_pull_request.base_ref).target_oid
          rescue => e
            Failbot.report(e)
            mark_failed(start_pull_request, message: "Failed to load current stack state")
            return
          end

          # TODO: Determine if we can skip this step in favour of short-circuiting
          # See https://github.com/github/git-contrib/issues/38#issuecomment-3871249388
          commit_pairs = ([base_oid] + pulls.filter_map { expected_head_oid_by_pr_number[_1.number.to_s] })
            .each_cons(2).map { |base, head| [head, base] }

          begin
            up_to_date = repository.rpc.descendant_of(commit_pairs)
          rescue => e
            Failbot.report(e)
            mark_failed(start_pull_request, message: "Failed to load current stack state")
            return
          end

          pulls.each do |pull_request|
            expected_head_oid = expected_head_oid_by_pr_number[pull_request.number.to_s]
            if expected_head_oid.nil?
              mark_failed(pull_request, message: "Stack contents have changed")
              return
            end

            head_ref = repository.heads.find(pull_request.head_ref)
            actual_head_oid = head_ref.target_oid
            if expected_head_oid != actual_head_oid
              mark_failed(pull_request, message: "Branch has moved")
              return
            end

            if up_to_date[[actual_head_oid, base_oid]]
              mark_successful(pull_request, old_head_oid: actual_head_oid, new_head_oid: actual_head_oid)
              base_oid = actual_head_oid
              next
            end

            result = GitSystems::CreateRebaseCommit.new(
              repository:,
              base_sha: base_oid,
              head_sha: actual_head_oid,
              name: actor.git_author_name,
              email: actor.git_author_email,
              timestamp: actor.time_zone.now,
              timeout: 1.second,
            ).call

            case result
            when GitSystems::Commit::Conflict
              mark_conflicted(pull_request)
              return
            when GitSystems::Commit::Error, GitSystems::Errors::Outage, GitSystems::Errors::Fatal, GitSystems::Errors::Timeout
              mark_failed(pull_request, message: "Failed to rebase")
              return
            when GitSystems::Commit::Created
              # No-op: success is handled after this case statement
            else
              T.absurd(result)
            end

            # TODO: Perform a single batched ref update at the end of the loop
            # Blocked by https://github.com/github/github/pull/416000
            batch_ref_update = GitSystems::BatchWriteRefs::Service.new(
              repository:,
              actor:,
              priority: :high,
            )
            batch_ref_update.add(
              ref_name: head_ref.qualified_name,
              before_oid: actual_head_oid,
              after_oid: result.sha,
            )
            ref_update_result = batch_ref_update.call

            if exception = ref_update_result.exception
              Failbot.report(exception)
              mark_failed(pull_request, message: "Failed to push rebase")
              return
            end

            mark_successful(pull_request, old_head_oid: actual_head_oid, new_head_oid: result.sha)
            base_oid = result.sha
          end

          status.mark_done
          with_retry(3) { status.save! }
        end
      end

      private

      sig do
        type_parameters(:R)
          .params(times: Integer, block: T.proc.returns(T.type_parameter(:R)))
          .returns(T.type_parameter(:R))
      end
      def with_retry(times, &block)
        block.call
      rescue
        raise if times <= 0

        times -= 1
        sleep 0.1
        retry
      end

      sig { returns(PullRequest) }
      memoize def start_pull_request = arguments.first[:start_pull_request]

      sig { returns(Repository) }
      def repository = T.must(start_pull_request.repository)

      sig { returns(PullRequests::Stack) }
      memoize def stack = T.must(start_pull_request.stack)

      sig { returns(UpdateAllBranches::Status) }
      memoize def status
        UpdateAllBranches::Status.find(stack:) ||
          UpdateAllBranches::Status.build(stack:, start_pull_request:)
      end

      sig { params(pull_request: PullRequest, message: String).void }
      def mark_failed(pull_request, message:)
        status.mark_failed(pull_request:, message:)
        status.save!
      end

      sig { params(pull_request: PullRequest).void }
      def mark_conflicted(pull_request)
        status.mark_conflicted(pull_request:)
        status.save!
      end

      sig { params(pull_request: PullRequest, old_head_oid: String, new_head_oid: String).void }
      def mark_successful(pull_request, old_head_oid:, new_head_oid:)
        status.mark_successful(pull_request:, old_head_oid:, new_head_oid:)

        begin
          # The status is saved multiple times during the job's lifecycle,
          # so if this one fails we will try again later.
          status.save!
        rescue => e
          Failbot.report(e)
        end
      end
    end
  end
end
