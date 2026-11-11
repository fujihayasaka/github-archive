# typed: strict
# frozen_string_literal: true

module PullRequests
  module Merge
    class Command
      include ICommand

      DATABASE_ERRORS = T.let([
        ActiveRecord::QueryCanceled,
        *Resiliency::Response::UnavailableExceptions
      ], T::Array[T.class_of(StandardError)])

      sig do
        params(
          pull_request: PullRequest,
          repository: Repository,
          actor: T.any(Bot, User, Integration),
          mode: Mode,
          runtime: Enums::Runtime,
          auto_merge_request: T.nilable(AutoMergeRequest)
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
        when rules.git_error_processing_rules?
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
        end

        case @mode
        when Mode::Queue
          if message = rules.invalid_merge_queue_configuration_message
            return Results::Invalid.new(reason: Enums::Validations::InvalidMergeQueueConfig, message:)
          end
        when Mode::Wait
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
        Result::MergeCommitCreated.new(oid: "TODO")
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
      rescue ActiveRecord::RecordNotUnique
        Result::DuplicateDatabaseRecord.new
      rescue => exception
        # TODO: Exhaustively case this.
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
            skip_prepare_and_validate: true,
          )
        rescue => exception
          return Result::Error.new(exception:, message: exception.message)
        end

        # TODO: When to disable auto merge request?
        # disable!(reason: ) Translate reason into enum
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
      def delete_merge_commit_request!
        Result::Success.new # TODO
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

      sig { params(reason: Enums::DisableReason).returns(SuccessOrError) }
      def disable!(reason:)
        @auto_merge_request&.destroy

        Result::Success.new
      rescue *DATABASE_ERRORS => exception
        ICommand::Result::Error.new(message: exception.message, exception:, permit_retry: true)
      rescue => exception
        # TODO: Exhaustively case this.
        Result::Error.new(message: exception.message, exception:)
      end

      sig { override.void }
      def publish_live_update!
        @pull_request.notify_socket_subscribers
        channel = GitHub::WebSocket::Channels.pull_request_state(@pull_request)
        GitHub::WebSocket.notify_pull_request_channel(@pull_request, channel)
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
            when Enums::Strategy::Merge
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
        end
      end

      sig { override.returns(SuccessOrError) }
      def request_cprmc!
        # TODO: Error handling.
        @pull_request.enqueue_mergeable_update
        Result::Success.new
      end

      private

      sig { returns(Rules) }
      def rules
        Rules.new(pull_request: @pull_request, repository: @repository, actor: @actor, mode: @mode)
      end
    end
  end
end
