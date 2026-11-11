# typed: strict
# frozen_string_literal: true

module PullRequests
  module Merge
    module Logging
      class Commands
        include ICommand

        class ActionCollection
          sig { void }
          def initialize
            @actions = T.let([], T::Array[Action])
          end

          sig { returns(T::Array[Action]) }
          def actions = @actions

          sig { returns(T::Array[String]) }
          def to_a = @actions.map(&:to_logging_s)

          sig { params(action: Action).void }
          def <<(action) = @actions << action
        end

        class Action < T::Struct
          const :name, Symbol
          const :context, T.nilable(String), default: nil
          const :duration_ms, Numeric, default: 0.0
          const :success, T::Boolean

          sig { returns(String) }
          def to_logging_s
            status = success ? "" : "[X] "
            timing = "(#{duration_ms}ms)"
            if context.present?
              "#{status}#{name}(#{context}) #{timing}"
            else
              "#{status}#{name} #{timing}"
            end
          end

          sig { params(other: T.untyped).returns(T::Boolean) }
          def ==(other)
            return false unless other.is_a?(Action)
            name == other.name && success == other.success
          end
        end

        sig { returns(ActionCollection) }
        attr_reader :actions

        # Keep this union type up to date as new commands are added to ICommand
        CommandResult = T.type_alias do
          T.any(
            ValidateResult,
            CreateAutoMergeRequestResult,
            CreateMergeCommitResult,
            PerformMergeResult,
            AddToMergeQueueResult,
            SuccessOrError,
            Result::NotMergeable,
            NilClass, # void methods
          )
        end

        sig { params(delegate: ICommand).void }
        def initialize(delegate:)
          @delegate = delegate
          @actions = T.let(ActionCollection.new, ActionCollection)
        end

        sig { override.returns(ValidateResult) }
        def validate!
          with_telemetry(:validate!) do
            @delegate.validate!
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
          with_telemetry(:create_auto_merge_request!, context: merge_method.to_s) do
            @delegate.create_auto_merge_request!(
              commit_title:,
              commit_message:,
              merge_method:,
              actor_ip_address:,
              commit_email_address_id:,
            )
          end
        end

        sig { override.returns(CreateMergeCommitResult) }
        def create_merge_commit!
          with_telemetry(:create_merge_commit!) do
            @delegate.create_merge_commit!
          end
        end

        sig { override.params(merge_commit_sha: T.nilable(String)).returns(PerformMergeResult) }
        def perform_merge!(merge_commit_sha:)
          with_telemetry(:perform_merge!) do
            @delegate.perform_merge!(merge_commit_sha: merge_commit_sha)
          end
        end

        sig { override.params(jump: T::Boolean, solo: T::Boolean).returns(AddToMergeQueueResult) }
        def add_to_merge_queue!(jump:, solo:)
          context = [("jump" if jump), ("solo" if solo)].compact.join(",")
          with_telemetry(:add_to_merge_queue!, context: context.presence) do
            @delegate.add_to_merge_queue!(jump:, solo:)
          end
        end

        sig { override.returns(SuccessOrError) }
        def delete_auto_merge_request!
          with_telemetry(:delete_auto_merge_request!) do
            @delegate.delete_auto_merge_request!
          end
        end

        sig { override.void }
        def emit_create_telemetry!
          with_telemetry(:emit_create_telemetry!, success: true) do
            @delegate.emit_create_telemetry!
          end
        end

        sig { override.params(reason: Enums::DisableReason).returns(SuccessOrError) }
        def emit_disabled_telemetry!(reason:)
          with_telemetry(:emit_disabled_telemetry!, context: reason.serialize.to_s) do
            @delegate.emit_disabled_telemetry!(reason:)
          end
        end

        sig { override.void }
        def publish_live_update!
          with_telemetry(:publish_live_update!, success: true) do
            @delegate.publish_live_update!
          end
        end

        sig { override.void }
        def request_auto_merge_job!
          with_telemetry(:request_auto_merge_job!, success: true) do
            @delegate.request_auto_merge_job!
          end
        end

        sig { override.returns(SuccessOrError) }
        def request_cprmc!
          with_telemetry(:request_cprmc!) do
            @delegate.request_cprmc!
          end
        end

        sig { override.params(name: Symbol).returns(T::Boolean) }
        def feature_enabled?(name)
          @delegate.feature_enabled?(name)
        end

        private

        sig do
          type_parameters(:T)
            .params(
              name: Symbol,
              context: T.nilable(String),
              success: T.nilable(T::Boolean),
              block: T.proc.returns(T.type_parameter(:T))
            ).returns(T.type_parameter(:T))
        end
        def with_telemetry(name, context: nil, success: nil, &block)
          start_time = Time.now
          result = block.call
          duration_ms = (Time.now - start_time) * 1000.0

          # Determine success/failure based on result type for logging and observability
          success ||= case typed_result = T.cast(result, CommandResult)
          when Result::Success,
               Result::MergeCommitCreated,
               NilClass # void methods return nil, consider them successful
            true
          when Result::Error,
               Result::StaleMergeCommit,
               Result::NotMergeable,
               Results::Invalid,
               Result::DuplicateDatabaseRecord,
               Result::TerminalBranchRuleFailure,
               Result::ResolvableBranchRuleFailure,
               Results::AlreadyMerged
            false
          else
            T.absurd(typed_result)
          end

          GitHub.dogstats.distribution(
            "pulls.merge.commands.duration",
            duration_ms,
            tags: ["action:#{name.to_s.delete_suffix("!")}"]
          )

          @actions << Action.new(
            name:, context:, success:,
            duration_ms: duration_ms.round(2),
          )

          result
        end

        sig { params(sha: T.nilable(String)).returns(String) }
        def short_sha(sha) = sha.to_s[0..6] || ""
      end
    end
  end
end
