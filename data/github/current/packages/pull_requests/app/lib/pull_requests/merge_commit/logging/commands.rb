# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module Logging
      # This class implements the ICommand interface, and delegates behavior to the relevant Command. This allows us
      # to inject logging without having to pollute the other Command implementations with logging details.
      class Commands
        include ICommand

        class ActionCollection
          sig { void }
          def initialize
            @actions = T.let([], T::Array[Action])
          end

          sig { returns(T::Array[String]) }
          def to_a
            @actions.map(&:to_logging_s)
          end

          sig { params(action: Action).void }
          def <<(action)
            @actions << action
          end

          sig { params(id: Numeric).returns(T::Array[String]) }
          def logs_for_pull_request_id(id)
            @actions.filter { |action| action.pull_request_ids.include?(id) }.map(&:to_logging_s)
          end
        end

        class Action < T::Struct
          const :name, Symbol
          const :context, T.nilable(String)
          const :pull_request_ids, T::Array[Integer]

          sig { returns(String) }
          def to_logging_s
            if context.present?
              "#{name}(#{context})"
            else
              "#{name}"
            end
          end
        end

        sig { returns(ActionCollection) }
        attr_reader :actions

        sig { params(delegate: ICommand).void }
        def initialize(delegate:)
          @delegate = delegate
          @actions = T.let(ActionCollection.new, ActionCollection)
        end

        sig do
          override.params(
            pull_request_id: Integer,
            priority: Enums::Priority,
            base_repository_id: Integer,
            head_repository_id: Integer,
            base_branch_sha: String,
            head_branch_sha: String,
            merge_sha: T.nilable(String),
            merge_state: MergeState,
            merge_conflict: T.nilable(T::Hash[T.untyped, T.untyped]),
            rebase_sha: T.nilable(String),
            rebase_state: RebaseState,
            rebase_conflict: T.nilable(T::Hash[T.untyped, T.untyped]),
            requested_at: Time,
          ).returns(InsertMergeCommitRequestResult)
        end
        def insert_merge_commit_request!(
          pull_request_id:,
          priority:,
          base_repository_id:,
          head_repository_id:,
          base_branch_sha:,
          head_branch_sha:,
          merge_sha:,
          merge_state:,
          merge_conflict:,
          rebase_sha:,
          rebase_state:,
          rebase_conflict:,
          requested_at:
        )
          with_telemetry(:insert_merge_commit_request!, { "pull_request_id" => pull_request_id }) do
            @actions << Action.new(
              name: :insert_merge_request!,
              pull_request_ids: [pull_request_id]
            )

            @delegate.insert_merge_commit_request!(
              pull_request_id:,
              priority:,
              base_repository_id:,
              head_repository_id:,
              base_branch_sha:,
              head_branch_sha:,
              merge_sha:,
              merge_state:,
              merge_conflict:,
              rebase_sha:,
              rebase_state:,
              rebase_conflict:,
              requested_at:,
            )
          end
        end

        sig { override.params(pull_request_id: Integer).returns(EnqueueBatchRefUpdatesJobResult) }
        def enqueue_batch_ref_updates_job!(pull_request_id:)
          with_telemetry(:enqueue_batch_ref_updates!, { "pull_request_id" => pull_request_id }) do
            @actions << Action.new(
              name: :enqueue_batch_ref_updates!,
              pull_request_ids: [pull_request_id]
            )

            @delegate.enqueue_batch_ref_updates_job!(pull_request_id:)
          end
        end

        sig { override.params(pull_request_ids: T::Array[Integer]).returns(TransitionToProcessingResult) }
        def transition_to_processing!(pull_request_ids:)
          with_telemetry(:transition_to_processing!, { "pull_request_ids" => pull_request_ids }) do
            @actions << Action.new(
              name: :transition_to_processing!,
              pull_request_ids:,
            )

            @delegate.transition_to_processing!(pull_request_ids:)
          end
        end

        sig { override.params(pull_request_id: Integer, head_sha: String, base_sha: String).returns(CreateMergeCommitResult) }
        def create_merge_commit!(pull_request_id:, head_sha:, base_sha:)
          with_telemetry(:create_merge_commit!, { "pull_request_id" => pull_request_id }) do
            @actions << Action.new(
              name: :create_merge_commit!,
              pull_request_ids: [pull_request_id]
            )

            @delegate.create_merge_commit!(pull_request_id:, head_sha:, base_sha:)
          end
        end

        sig { override.params(pull_request_id: Integer, base_sha: String, merge_commit_sha: String, timeout: Integer).returns(CreateRebaseCommitResult) }
        def create_rebase_commit!(pull_request_id:, base_sha:, merge_commit_sha:, timeout:)
          with_telemetry(:create_rebase_commit!, { "pull_request_id" => pull_request_id, "merge_commit_sha" => merge_commit_sha, "timeout" => timeout }) do
            @actions << Action.new(
              name: :create_rebase_commit!,
              pull_request_ids: [pull_request_id],
              context: short_sha(merge_commit_sha),
            )

            @delegate.create_rebase_commit!(pull_request_id:, base_sha:, merge_commit_sha:, timeout:)
          end
        end

        sig { override.params(updates: T::Array[PullRequests::MergeCommit::ICommand::RefUpdate]).returns(UpdateRefsResult) }
        def update_refs!(updates:)
          with_telemetry(:update_refs!, { "pull_request_ids" => updates.map(&:pull_request_id), "total" => updates.size }) do
            updates.each do |update|
              @actions << Action.new(
                name: :update_refs!,
                pull_request_ids: [update.pull_request_id],
                context: "#{update.name} => #{short_sha(update.sha)}"
              )
            end

            @delegate.update_refs!(updates:)
          end
        end

        sig { override.params(pull_request_id: Integer, merge_commit_sha: String).returns(MarkPullRequestAsMergeableResult) }
        def mark_pull_request_as_mergeable!(pull_request_id:, merge_commit_sha:)
          with_telemetry(:mark_pull_request_as_mergeable!, { "pull_request_id" => pull_request_id }) do
            @actions << Action.new(
              name: :mark_pull_request_as_mergeable!,
              pull_request_ids: [pull_request_id],
              context: short_sha(merge_commit_sha),
            )

            @delegate.mark_pull_request_as_mergeable!(pull_request_id:, merge_commit_sha:)
          end
        end

        sig { override.params(pull_request_id: Integer).returns(MarkPullRequestAsUnmergeableResult) }
        def mark_pull_request_as_unmergeable!(pull_request_id:)
          with_telemetry(:mark_pull_request_as_mergeable!, { "pull_request_id" => pull_request_id }) do
            @actions << Action.new(
              name: :mark_pull_request_as_unmergeable!,
              pull_request_ids: [pull_request_id],
            )

            @delegate.mark_pull_request_as_unmergeable!(pull_request_id:)
          end
        end

        sig do
          override.params(
            pull_request_id: Integer,
            details: T::Hash[T.untyped, T.untyped],
            type: Enums::Conflict
          ).returns(GenericResult)
        end
        def store_conflicts!(pull_request_id:, details:, type:)
          @actions << Action.new(
            name: :store_conflicts!,
            pull_request_ids: [pull_request_id],
            context: type.serialize,
          )

          @delegate.store_conflicts!(pull_request_id:, details:, type:)
        end

        sig do
          override.params(
            pull_request_id: Integer,
            type: Enums::Conflict
          ).returns(GenericResult)
        end
        def clear_conflicts!(pull_request_id:, type:)
          @actions << Action.new(
            name: :clear_conflicts!,
            pull_request_ids: [pull_request_id],
            context: type.serialize,
          )

          @delegate.clear_conflicts!(pull_request_id:, type:)
        end

        sig { override.params(pull_request_id: Integer).returns(ClearMergeabilityResult) }
        def clear_mergeability!(pull_request_id:)
          with_telemetry(:clear_mergeability!, { "pull_request_id" => pull_request_id }) do
            @actions << Action.new(
              name: :clear_mergeability!,
              pull_request_ids: [pull_request_id]
            )

            @delegate.clear_mergeability!(pull_request_id:)
          end
        end

        sig { override.params(pull_request_ids: T::Array[Integer]).returns(DeleteProcessingRequestsResult) }
        def delete_processing_requests!(pull_request_ids:)
          with_telemetry(:delete_processing_requests!, { "pull_request_ids" => pull_request_ids }) do
            @actions << Action.new(
              name: :delete_processing_requests!,
              pull_request_ids:,
            )

            @delegate.delete_processing_requests!(pull_request_ids:)
          end
        end

        sig { override.params(pull_request_id: Integer).returns(DispatchMergabilityResult) }
        def dispatch_mergeability_event!(pull_request_id:)
          with_telemetry(:dispatch_mergeability_event!, { "pull_request_id" => pull_request_id }) do
            @actions << Action.new(
              name: :dispatch_mergeability_event!,
              pull_request_ids: [pull_request_id],
            )

            @delegate.dispatch_mergeability_event!(pull_request_id:)
          end
        end

        sig { override.params(name: Symbol).returns(T::Boolean) }
        def feature_enabled?(name)
          @delegate.feature_enabled?(name)
        end

        sig do
          override.params(
            pull_request_id: Integer,
            base_sha: String,
            head_sha: String
          ).returns(SimulateMergeCommitCreationResult)
        end
        def simulate_merge_commit_creation!(pull_request_id:, base_sha:, head_sha:)
          Rails.logger.mine("calling simulate from logging commands")
          with_telemetry(:simulate_merge_commit_creation!, { "pull_request_id" => pull_request_id }) do
            @actions << Action.new(
              name: :simulate_merge_commit_creation!,
              pull_request_ids: [pull_request_id]
            )

            @delegate.simulate_merge_commit_creation!(pull_request_id:, base_sha:, head_sha:)
          end
        end

        private

        # Add timings and spans to the various commands so we can get more granular insight in to them.
        sig do
          type_parameters(:T)
            .params(name: Symbol, attributes: T::Hash[String, T.untyped], block: T.proc.returns(T.type_parameter(:T)))
            .returns(T.type_parameter(:T))
        end
        def with_telemetry(name, attributes, &block)
          GitHub.tracer.in_span("merge_commits.commands.#{name}", kind: :internal, attributes:) do
            GitHub.dogstats.distribution_time("merge_commits.commands.duration", tags: ["action:#{name.to_s.delete_suffix("!")}"], &block)
          end
        end

        sig { params(sha: T.nilable(String)).returns(String) }
        def short_sha(sha)
          sha.to_s[0..6] || ""
        end
      end
    end
  end
end
