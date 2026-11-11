# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    module UpdateAllBranches
      class Service < BaseService
        include GitHub::Memoizer

        class Success; end

        Result = T.type_alias { T.any(Success, Stacks::Error) }
        ResultType = type_member { { fixed: Result } }

        sig do
          params(
            start_pull_request: ::PullRequest,
            actor: ::User,
            expected_head_oid_by_pr_number: T::Hash[String, String],
            log_context: T::Hash[String, String],
          ).returns(Result)
        end
        def self.call(
          start_pull_request:,
          actor:,
          expected_head_oid_by_pr_number:,
          log_context: {}
        )
          new(start_pull_request:, actor:, expected_head_oid_by_pr_number:, log_context:).call
        end

        sig do
          params(
            start_pull_request: ::PullRequest,
            actor: ::User,
            expected_head_oid_by_pr_number: T::Hash[String, String],
            log_context: T::Hash[String, String],
          ).void
        end
        def initialize(
          start_pull_request:,
          actor:,
          expected_head_oid_by_pr_number:,
          log_context: {}
        )
          @start_pull_request = start_pull_request
          @actor = actor
          @expected_head_oid_by_pr_number = expected_head_oid_by_pr_number
          super(log_context:)
        end

        sig { override.returns(String) }
        def metric_key = "update_all_branches"

        sig { override.returns(String) }
        def human_name = "Update all stacked branches"

        sig { override.returns(T::Hash[String, T.untyped]) }
        def service_log_context = {
          "gh.actor.id" => @actor.id,
          "gh.repo.id" => repository.id,
          "gh.pull_request.stack.id" => @start_pull_request.stack&.id,
        }

        sig { override.returns(Result) }
        def perform
          stack = @start_pull_request.stack
          if stack.nil?
            return logged_error_result(
              Error::FailureReason::NotStacked,
              pulls: [@start_pull_request],
            )
          end

          pulls = stack.pulls_from(@start_pull_request)

          begin
            base_oid = repository.heads.find(@start_pull_request.base_ref).target_oid
          rescue => exception
            Failbot.report(exception)
            mark_failed(@start_pull_request, message: "Failed to load current stack state")
            return logged_error_result(
              Error::FailureReason::GitReadError,
              exception:,
              details: { "git.operation" => "load ref" },
            )
          end

          # TODO: Determine if we can skip this step in favour of short-circuiting
          # See https://github.com/github/git-contrib/issues/38#issuecomment-3871249388
          commit_pairs = ([base_oid] + pulls.filter_map { @expected_head_oid_by_pr_number[_1.number.to_s] })
            .each_cons(2).map { |base, head| [head, base] }

          begin
            up_to_date = repository.rpc.descendant_of(commit_pairs)
          rescue => exception
            Failbot.report(exception)
            mark_failed(@start_pull_request, message: "Failed to load current stack state")
            return logged_error_result(
              Error::FailureReason::GitReadError,
              exception:,
              details: { "git.operation" => "descendant_of" },
            )
          end

          previous_head_oid = base_oid
          pulls.each do |pull_request|
            expected_head_oid = @expected_head_oid_by_pr_number[pull_request.number.to_s]
            if expected_head_oid.nil?
              mark_failed(pull_request, message: "Stack contents have changed")
              return logged_error_result(
                Error::FailureReason::StackContentsMismatch,
                pulls: [pull_request],
              )
            end

            begin
              head_ref = repository.heads.find(pull_request.head_ref)
            rescue => head_ref_exception
              Failbot.report(head_ref_exception)
              mark_failed(pull_request, message: "Failed to load current stack state")
              return logged_error_result(
                Error::FailureReason::GitReadError,
                pulls: [pull_request],
                exception: head_ref_exception,
                details: { "git.operation" => "load ref" },
              )
            end

            actual_head_oid = head_ref.target_oid
            if expected_head_oid != actual_head_oid
              mark_failed(pull_request, message: "Branch has moved")
              return logged_error_result(
                Error::FailureReason::StackContentsMismatch,
                pulls: [pull_request],
                details: {
                  "expected_head_oid" => expected_head_oid,
                  "actual_head_oid" => actual_head_oid,
                }
              )
            end

            if up_to_date[[actual_head_oid, base_oid]]
              mark_successful(pull_request, old_head_oid: actual_head_oid, new_head_oid: actual_head_oid)
              base_oid = actual_head_oid
              previous_head_oid = actual_head_oid
              next
            end

            # NOTE: We need to use the Spokes version of rebase instead of
            #  the GitRPC version for `--onto` support. This code should use
            #  `GitSystems::CreateRebaseCommit` when it has been migrated to
            #  Spokes.
            begin
              result = with_retry(attempts: 2, exception: SpokesAPI::ResourceExhausted) do
                repository.spokes_api.with_transaction do
                  repository.spokes_api.rebase( # rubocop:disable GitHub/EnsureCommitAttribution
                    head_oid: actual_head_oid,
                    base_oid: previous_head_oid,
                    onto_oid: base_oid,
                    committer: {
                      name: @actor.git_author_name,
                      email: @actor.git_author_email,
                      time: @actor.time_zone.now,
                    },
                    mergeability_only: false,
                    committer_only: false,
                  )
                end
              end
            rescue => rebase_error
              mark_failed(pull_request, message: "Failed to rebase")
              return logged_error_result(
                Error::FailureReason::GitWriteError,
                exception: rebase_error,
                pulls: [pull_request],
                details: {
                  "git.operation" => "rebase",
                  "rebase.head_oid" => actual_head_oid,
                  "rebase.base_oid" => previous_head_oid,
                  "rebase.onto_oid" => base_oid,
                },
              )
            end

            rebased_oid = nil
            case result.rebase_status
            when :STATUS_SUCCESS, :STATUS_ALREADY_MERGED
              rebased_oid = result.oid&.id
            when :STATUS_MERGE_CONFLICT
              mark_conflicted(pull_request)
              return logged_error_result(
                Error::FailureReason::MergeConflict,
                pulls: [pull_request],
              )
            end

            if rebased_oid.nil?
              # This should not happen, unless:
              # - We get a malformed success response without an OID
              # - We get an unexpected `rebase_status` that we don't know how to
              #   handle.
              mark_failed(pull_request, message: "Failed to rebase")
              return logged_error_result(
                Error::FailureReason::GitWriteError,
                pulls: [pull_request],
                details: {
                  "git.operation" => "rebase",
                  "git.rebase_status" => result.rebase_status.to_s,
                  "git.rebased_oid" => rebased_oid.inspect,
                }
              )
            end

            if FeatureFlag.vexi.enabled?(:git_commits_via_push_job, repository, default: false)
              AuthenticCommits::CommitContext.push_range(base_oid, rebased_oid)
            end

            # TODO: Perform a single batched ref update at the end of the loop
            # Blocked by https://github.com/github/github/pull/416000
            batch_ref_update = GitSystems::BatchWriteRefs::Service.new(
              repository:,
              actor: @actor,
              priority: :high,
            )
            batch_ref_update.add(
              ref_name: head_ref.qualified_name,
              before_oid: actual_head_oid,
              after_oid: rebased_oid,
            )
            ref_update_result = batch_ref_update.call

            if ref_update_exception = ref_update_result.exception
              Failbot.report(ref_update_exception)
              mark_failed(pull_request, message: "Failed to push rebase")
              return logged_error_result(Error::FailureReason::GitWriteError, exception: ref_update_exception)
            end

            mark_successful(pull_request, old_head_oid: actual_head_oid, new_head_oid: rebased_oid)
            base_oid = rebased_oid
            previous_head_oid = actual_head_oid
          end

          status.mark_done
          with_retry(attempts: 3, exception: StandardError) { status.save! }
          notify_mergability_state_channels(pulls)

          record_success_outcome
          Success.new
        end

        private

        sig do
          type_parameters(:R)
            .params(attempts: Integer, exception: T.class_of(Exception), block: T.proc.returns(T.type_parameter(:R)))
            .returns(T.type_parameter(:R))
        end
        def with_retry(attempts:, exception:, &block)
          block.call
        rescue
          raise if attempts <= 0

          attempts -= 1
          sleep 0.1
          retry
        end

        sig { returns(Repository) }
        def repository = T.must(@start_pull_request.repository)

        sig { returns(UpdateAllBranches::Status) }
        memoize def status
          stack = T.must(@start_pull_request.stack)
          UpdateAllBranches::Status.find(stack:) ||
            UpdateAllBranches::Status.build(stack:, start_pull_request: @start_pull_request)
        end

        sig { params(pulls: T::Array[PullRequest]).void }
        def notify_mergability_state_channels(pulls)
          pulls.each do |pull_request|
            pull_request.notify_git_merge_state_channel
          end
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
end
