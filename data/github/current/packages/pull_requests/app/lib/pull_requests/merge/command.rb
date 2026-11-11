# typed: strict
# frozen_string_literal: true

module PullRequests
  module Merge
    class Command
      include ICommand

      DATABASE_ERRORS = T.let([
        ActiveRecord::QueryCanceled,
        *Resiliency::Response::UnavailableExceptions,
      ], T::Array[T.class_of(StandardError)])

      sig do
        params(
          pull_request: PullRequest,
          repository: Repository,
          actor: T.any(Bot, User, Integration),
          mode: Mode,
          runtime: Enums::Runtime,
          auto_merge_request: T.nilable(AutoMergeRequest),
        ).void
      end
      def initialize(pull_request:, repository:, actor:, mode:, runtime:, auto_merge_request: nil)
        @pull_request = pull_request
        @repository = repository
        @actor = actor
        @mode = mode
        @runtime = runtime
        @auto_merge_request = auto_merge_request
      end

      sig { returns(T.nilable(AutoMergeRequest)) }
      attr_reader :auto_merge_request

      sig { override.returns(ValidateResult) }
      def validate!
        case
        when rules.git_error_processing_rules? && @pull_request.merge_commit_sha.present?
          return ICommand::Result::Error.new(
            message: "Unable to evaluate merge requirements due to a Git processing error"
          )
        when @pull_request.merged?
          return Results::AlreadyMerged.new
        when rules.disabled_on_advisory_workspaces?
          return Results::Invalid.new(
            reason: Enums::Validations::AdvisoryWorkspace,
            message: "Temporary private forks do not support auto merge"
          )
        when rules.pull_request_user_states.failed?
          return Results::Invalid.new(
            reason: Enums::Validations::InvalidUserState,
            message: rules.pull_request_user_states.message
          )
        when rules.pull_request_merge_conflict_states.failed?
          return Results::Invalid.new(
            reason: Enums::Validations::MergeConflict,
            message: rules.pull_request_merge_conflict_states.message
          )
        when rules.pull_request_merge_methods.failed?
          return Results::Invalid.new(
            reason: Enums::Validations::MergeStrategyNotAllowed,
            message: rules.pull_request_merge_methods.message
          )
        when rules.pull_request_states.failed?
          return Results::Invalid.new(
            reason: Enums::Validations::InvalidPullRequestState,
            message: rules.pull_request_states.message
          )
        when rules.pull_request_repo_states.failed?
          return Results::Invalid.new(
            reason: Enums::Validations::InvalidRepositoryState,
            message: rules.pull_request_repo_states.message
          )
        when (stack_condition = rules.stack_condition)&.failed?
          return Results::Invalid.new(
            reason: Enums::Validations::InvalidStackState,
            message: stack_condition.message || "Stacked pull request has an unknown error"
          )
        end

        unless stacked?
          # for legacy branch protection
          unless base_branch_rule_evaluator = @pull_request.base_branch_rule_evaluator
            return Results::Invalid.new(
              reason: Enums::Validations::BranchRuleFailure,
              message: "Protected branch rules not configured for this branch"
            )
          end

          unless base_branch_rule_evaluator.authorized?(@actor)
            return Results::Invalid.new(
              reason: Enums::Validations::BranchRuleFailure,
              message: "User is not authorized for this protected branch"
            )
          end

          if [
            base_branch_rule_evaluator.pull_request_reviews_enabled?,
            base_branch_rule_evaluator.required_status_checks_enabled?,
            base_branch_rule_evaluator.required_review_thread_resolution_enabled?,
            base_branch_rule_evaluator.code_scanning_enabled?
          ].none?
            return Results::Invalid.new(
              reason: Enums::Validations::BranchRuleFailure,
              message: "Branch does not have required protected branch rules"
            )
          end
        end

        case @mode
        when Mode::Queue, Mode::StackedQueue
          unless stacked?
            if message = rules.invalid_merge_queue_configuration_message
              return Results::Invalid.new(reason: Enums::Validations::InvalidMergeQueueConfig, message:)
            end
          end
        when Mode::Wait, Mode::StackedWait
          unless stacked?
            case
            when rules.auto_merge_disallowed?
              return Results::Invalid.new(
                reason: Enums::Validations::AutoMergeNotAllowed,
                message: "Auto merge is not allowed for this repository"
              )
            when rules.auto_merge_not_available?
              return Results::Invalid.new(
                reason: Enums::Validations::AutoMergeCanNotBeAllowed,
                message: "Auto merge cannot be allowed for this repository"
              )
            end
          end

          # For cross-fork PRs, check that actor can push to the head (source) repository
          # This matches legacy can_enable_auto_merge behavior which checks both:
          # repository.async_pushable_by?(actor) && base_repository.async_pushable_by?(actor)
          head_repo = @pull_request.repository
          if head_repo.nil? || !head_repo.async_pushable_by?(@actor).sync
            return Results::Invalid.new(
              reason: Enums::Validations::ActorNotAuthorized,
              message: "User is not allowed to push to this repository"
            )
          end
        end

        terminal_rule_failures = rules.terminal_rule_failures

        if terminal_rule_failures.any?
          return Result::TerminalBranchRuleFailure.new(
            rules: terminal_rule_failures.map(&:type),
            messages: terminal_rule_failures.map(&:message),
          )
        end

        resolvable_rule_failures = rules.resolvable_rule_failures

        if resolvable_rule_failures.any?
          return Result::ResolvableBranchRuleFailure.new(
            rules: resolvable_rule_failures.map(&:type),
            messages: resolvable_rule_failures.map(&:message),
          )
        end

        Result::Success.new
      end

      sig { override.returns(CreateMergeCommitResult) }
      def create_merge_commit!
        merge_commit_command = PullRequests::MergeCommit::Command.new(
          pull_requests: [@pull_request],
          repository: @repository,
        )

        result = merge_commit_command.create_merge_commit!( # rubocop:disable GitHub/EnsureCommitAttribution
          pull_request_id: @pull_request.id,
          head_sha: @pull_request.head_sha,
          base_sha: @pull_request.base_sha,
        )

        case result
        when PullRequests::GitSystems::Commit::Created
          Result::MergeCommitCreated.new(oid: result.sha)
        when PullRequests::GitSystems::Commit::Conflict
          Result::Error.new(
            message: "failed: merge conflict encountered.",
            permit_retry: false
          )
        when PullRequests::GitSystems::Errors::Timeout
          Result::Error.new(
            message: "timed out: #{result.exception.message}",
            exception: result.exception,
            permit_retry: true
          )
        when PullRequests::GitSystems::Errors::Outage
          Result::Error.new(
            message: "outage: #{result.exception.message}",
            exception: result.exception,
            permit_retry: true
          )
        when PullRequests::GitSystems::Commit::Failed
          Result::Error.new(
            message: "failed to create merge commit.",
          )
        when PullRequests::GitSystems::Errors::Fatal
          Result::Error.new(
            message: "fatal error: #{result.exception.message}",
            exception: result.exception,
            permit_retry: false
          )
        when PullRequests::MergeCommit::ICommand::Result::Error
          Result::Error.new(
            message: "delegate error: #{result.exception&.message}",
            exception: result.try(:exception),
            permit_retry: result.respond_to?(:permit_retry) ? result.permit_retry : false
          )
        when PullRequests::MergeCommit::ICommand::Result::Timeout
          Result::Error.new(
            message: "timed out while creating merge commit: #{result.exception&.message}",
            exception: result.exception,
            permit_retry: true
          )
        else
          T.absurd(result)
        end
      end

      sig do
        override.params(
          commit_title: T.nilable(String),
          commit_message: T.nilable(String),
          merge_method: Symbol,
          actor_ip_address: T.nilable(String),
          commit_email_address_id: T.nilable(Integer),
        ).returns(CreateAutoMergeRequestResult)
      end
      def create_auto_merge_request!(commit_title:, commit_message:, merge_method:, actor_ip_address:, commit_email_address_id:)
        @pull_request.create_auto_merge_request!(
          user: @actor,
          commit_email_address_id:,
          commit_title:,
          commit_message:,
          actor_ip_address:,
          mode: @mode.type,
          mode_configuration: @mode.serialize,
          merge_method:,
          skip_create_callbacks: true,
        )

        Result::Success.new
      rescue ActiveRecord::RecordInvalid => exception
        # Validation failed
        Result::Error.new(message: exception.record.errors.full_messages.to_sentence, permit_retry: false, exception: exception)
      rescue ActiveRecord::RecordNotUnique
        # Duplicate auto merge request
        Result::DuplicateDatabaseRecord.new
      rescue ActiveRecord::ConnectionTimeoutError,
            ActiveRecord::Deadlocked,
            ActiveRecord::LockWaitTimeout,
            *DATABASE_ERRORS => exception
        # Transient database errors should retry
        Result::Error.new(message: exception.message, exception:, permit_retry: true)
      rescue ArgumentError => exception
        # Invalid arguments, e.g. invalid enum value
        Result::Error.new(message: exception.message, exception:)
      rescue OpenSSL::SSL::SSLError => exception
        # transient SSL errors should retry
        Result::Error.new(message: exception.message, exception:, permit_retry: true)
      rescue => exception
        # Catch all
        Result::Error.new(exception:, message: exception.message)
      end

      sig { override.params(merge_commit_sha: T.nilable(String)).returns(PerformMergeResult) }
      def perform_merge!(merge_commit_sha:)
        if @pull_request.merged?
          return Results::AlreadyMerged.new
        end

        unless @auto_merge_request && @pull_request.auto_merge_request == @auto_merge_request
          return Result::Error.new(message: "No auto merge request found for this pull request")
        end

        reflog_data = {}
        reflog_data[:real_ip] = @auto_merge_request.actor_ip_address if @auto_merge_request.actor_ip_address

        # author_email should be nil if user.author_emails returns an empty array
        # otherwise the merge will fail with an ArgumentError
        author_email =
          if @auto_merge_request.user&.author_emails.empty?
            nil
          else
            @auto_merge_request.commit_email_address&.email
          end

        prepare_only = FeatureFlag.vexi.enabled?(:am_refactor_prepare_only, @repository, default: false)

        begin
          orchestration = PullRequests::Orchestrations::Merge.create(
            repository: @repository,
            pull_request: @pull_request,
            actor: @actor,
            method: @auto_merge_request.minimal_merge_method, # TODO: replace with @auto_merge_request.strategy
            commit_title: @auto_merge_request.commit_title,
            commit_body: @auto_merge_request.commit_message,
            commit_author_email: author_email,
            merge_commit_sha: merge_commit_sha,
            source: nil, # TODO: I think this is where bypassBranchProtections can be passed in
            reflog_data: reflog_data,
            prepare_only: prepare_only,
          )
        rescue => exception
          return Result::Error.new(exception:, message: exception.message)
        end

        # TODO: If anything other than Success or :parent_mismatch is returned, disable the auto merge request
        begin
          orchestration.execute!
        rescue Orchestration::ValidationError
          Result::Error.new(
            message: orchestration.errors.full_messages.join(", "),
            error_code: orchestration.git_error_code,
          )
        rescue => exception
          Result::Error.new(exception:, message: exception.message)
        else
          if orchestration.skipped? || orchestration.failed?
            Result::Error.new(
              message: orchestration.error_message,
              error_code: orchestration.git_error_code,
            )
          else
            Result::Success.new
          end
        end
      end

      sig { override.params(jump: T::Boolean, solo: T::Boolean).returns(AddToMergeQueueResult) }
      def add_to_merge_queue!(jump:, solo:)
        Result::Success.new # TODO
      end

      sig { override.returns(SuccessOrError) }
      def delete_auto_merge_request!
        begin
          if !@auto_merge_request
            return Result::Error.new(message: "Auto merge request not found")
          end

          @auto_merge_request.destroy
          Result::Success.new
        rescue ActiveRecord::ConnectionTimeoutError,
              ActiveRecord::Deadlocked,
              ActiveRecord::LockWaitTimeout,
              *DATABASE_ERRORS => exception
          # Transient database errors should retry
          Result::Error.new(message: exception.message, exception: exception, permit_retry: true)
        rescue => exception
          # Catch all
          Result::Error.new(exception: exception, message: exception.message)
        end
      end

      sig { override.params(reason: Enums::DisableReason).returns(SuccessOrError) }
      def emit_disabled_telemetry!(reason:)
        @pull_request.create_issue_event(:auto_merge_disabled, @actor, message: reason.serialize) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

        unfulfilled_reason_codes = rules.unfulfilled_protected_branch_policy_reason_codes

        GlobalInstrumenter.instrument("pull_request.auto_merge_disable",
          {
            actor: @actor,
            repository: @repository,
            pull_request: @pull_request,
            disabled_message: reason.serialize,
            protected_branch: @pull_request.base_branch_rule_evaluator&.original_protected_branch,
            unfulfilled_protected_branch_policy_reason_codes: unfulfilled_reason_codes,
            auto_merge_request: @auto_merge_request
          }
        )

        @pull_request.instrument(
          :auto_merge_disabled,
          actor: @actor,
          reason: reason.readable_message
        )

        Result::Success.new
      end

      sig { params(reason: T.nilable(T.any(Enums::DisableReason, Symbol))).returns(SuccessOrError) }
      def disable!(reason:)
        return Result::Error.new(message: "Must provide a disable reason") if reason.nil?

        disable_reason = reason.is_a?(Enums::DisableReason) ? reason : Enums::DisableReason.try_deserialize(reason)
        return Result::Error.new(message: "Invalid disable reason: #{reason}") if disable_reason.nil?

        if disable_reason == Enums::DisableReason::ManuallyDisabled && @actor.nil?
          return Result::Error.new(message: "Actor must be present when manually disabling auto merge")
        end

        delete_auto_merge_request!
      end

      sig { override.void }
      def publish_live_update!
        @pull_request.notify_socket_subscribers
        channel = GitHub::WebSocket::Channels.pull_request_state(@pull_request)
        GitHub::WebSocket.notify_pull_request_channel(@pull_request, channel)
      end

      sig { override.params(enqueue_reason: T.nilable(String)).void }
      def request_auto_merge_job!(enqueue_reason: nil)
        AutoMergeJob.perform_later(@pull_request, enqueue_reason:)
      end

      sig { override.params(name: Symbol).returns(T::Boolean) }
      def feature_enabled?(name)
        @repository.feature_flag_enabled?(name, default: false)
      end

      sig { override.void }
      def emit_create_telemetry!
        # TODO: Run this in a background job.
        case @mode
        when Mode::Wait
          event = begin
            case strategy = @mode.strategy
            when Enums::Strategy::Squash
              "auto_squash_enabled"
            when Enums::Strategy::Rebase
              "auto_rebase_enabled"
            when Enums::Strategy::Merge, Enums::Strategy::Stack
              "auto_merge_enabled"
            else T.absurd(strategy)
            end
          end

          @pull_request.create_issue_event(event, @actor) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

          GlobalInstrumenter.instrument("pull_request.auto_merge_enable",
            {
              actor: @actor,
              repository: @repository,
              pull_request: @pull_request,
              auto_merge_request: @auto_merge_request,
              protected_branch: @pull_request.base_branch_rule_evaluator&.original_protected_branch,
              unfulfilled_protected_branch_policy_reason_codes: rules.unfulfilled_protected_branch_policy_reason_codes,
            }
          )

          # This triggers the HookEventSubscriber to queue the webhook delivery
          @pull_request.instrument(:auto_merge_enabled, actor: @actor)
        end
      end

      sig { override.returns(SuccessOrError) }
      def request_cprmc!
        @pull_request.enqueue_mergeable_update
        Result::Success.new
      rescue ActiveRecord::ConnectionTimeoutError,
            ActiveRecord::Deadlocked,
            ActiveRecord::LockWaitTimeout,
            *DATABASE_ERRORS => exception
        # Transient database errors should retry
        Result::Error.new(message: exception.message, exception:, permit_retry: true)
      rescue => exception
        # Catch all
        Result::Error.new(exception:, message: exception.message)
      end

      sig { returns(Rules) }
      def rules
        Rules.new(pull_request: @pull_request, repository: @repository, actor: @actor, mode: @mode)
      end

      private

      sig { returns(T::Boolean) }
      def stacked?
        case @mode
        when Mode::StackedQueue, Mode::StackedWait
          true
        else
          false
        end
      end
    end
  end
end
