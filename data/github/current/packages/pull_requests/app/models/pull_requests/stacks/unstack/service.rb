# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    module Unstack
      class Service < BaseService
        class Success; end

        Result = T.type_alias { T.any(Success, Error) }
        ResultType = type_member { { fixed: Result } }

        sig { params(stack: Stack, actor: User, log_context: T::Hash[String, String]).returns(Result) }
        def self.call(stack, actor:, log_context: {})
          new(stack, actor:, log_context:).call
        end

        sig { params(stack: Stack, actor: User, log_context: T::Hash[String, String]).void }
        def initialize(stack, actor:, log_context: {})
          @stack = stack
          @actor = actor
          super(log_context:)
        end

        sig { override.returns(String) }
        def metric_key = "unstack"

        sig { override.returns(String) }
        def human_name = "Unstack pulls"

        sig { override.returns(T::Hash[String, T.untyped]) }
        def service_log_context = {
          "gh.pull_request_stacks.id" => @stack.id,
        }

        sig { override.returns(Result) }
        def perform
          pull_requests = @stack.pull_requests.to_a

          unless FeatureFlag.vexi.enabled?(:pull_request_stacks_prevent_unstacking_locked_prs, @stack.repository, default: false)
            # Do not allow unstacking if any pull request in the stack has auto-merge enabled
            # We're unable to call the private `PullRequest#auto_merge_enabled?` method here, so instead we'll borrow its logic.
            GitHub::PrefillAssociations.prefill_associations(pull_requests, [:auto_merge_request])
            pulls_with_auto_merge = pull_requests.select { _1.auto_merging? }
            if pulls_with_auto_merge.any?
              return logged_error_result(
                Error::FailureReason::AutoMergeEnabled,
                pulls: pulls_with_auto_merge,
              )
            end
          end

          # Prefill base_repository and stack on each pull request to avoid N+1 queries
          # when the merge_queue batch_method accesses stack_or_pull_base_ref_name
          # (which reads base_repository and stack). The scoped has_one :stack_entry
          # prevents available_records matching for :stack, so we set the target
          # directly (same pattern as PrefillAssociations.prefill_association).
          GitHub::PrefillAssociations.prefill_associations(
            pull_requests, :base_repository,
            available_records: [@stack.repository]
          )
          pull_requests.each do |pull|
            pull.association(:stack).target = @stack # rubocop:disable GitHub/DontCallAssociationTargetEquals
          end
          GitHub::PrefillAssociations.prefill_batch_method(pull_requests, :merge_queue)
          merge_queues = pull_requests.filter_map(&:merge_queue).uniq
          GitHub::PrefillAssociations.prefill_associations(merge_queues, [:entries])

          if FeatureFlag.vexi.enabled?(:pull_request_stacks_prevent_unstacking_locked_prs, @stack.repository, default: false)
            GitHub::PrefillAssociations.prefill_associations(pull_requests, [:auto_merge_request])

            locked_pulls = []
            pull_ids_to_remove = []
            pull_requests.each do |pull|
              if pull.stack_operation_locked?
                locked_pulls << pull
              else
                pull_ids_to_remove << pull.id
              end
            end

            if pull_ids_to_remove.empty?
              return logged_error_result(
                Error::FailureReason::AllPullsLocked,
                pulls: locked_pulls,
              )
            end

            repository = @stack.repository
            removed_pulls = pull_requests.select { pull_ids_to_remove.include?(_1.id) }
            remaining_stack_size = pull_requests.size - removed_pulls.count

            # Capture stack metadata before destroy for Hydro instrumentation,
            # since entries (and thus base_sha) won't be available after destroy.
            hydro_payload = {
              event_type: :UNSTACKED,
              stack_id: @stack.id,
              stack_number: @stack.number,
              stack_base_branch: @stack.base_ref,
              repository: repository,
              pull_requests_affected: removed_pulls,
              stack_size: remaining_stack_size,
              actor: @actor,
            }

            ActiveRecord::Base.connected_to(role: :writing) do
              @stack.entries.where(pull_request_id: pull_ids_to_remove).destroy_all
              @stack.destroy! unless @stack.entries.exists?
            end
          else
            # Do not allow unstacking if any pull request in the stack is queued for merge
            enqueued_pulls = pull_requests.select(&:in_merge_queue?)
            if enqueued_pulls.any?
              return logged_error_result(
                Error::FailureReason::InMergeQueue,
                pulls: enqueued_pulls,
              )
            end

            # Capture stack metadata before destroy for Hydro instrumentation,
            # since entries (and thus base_sha) won't be available after destroy.

            repository = @stack.repository
            hydro_payload = {
              event_type: :UNSTACKED,
              stack_id: @stack.id,
              stack_number: @stack.number,
              stack_base_branch: @stack.base_ref,
              repository: repository,
              pull_requests_affected: pull_requests,
              stack_size: 0,
              actor: @actor,
            }
            ActiveRecord::Base.connected_to(role: :writing) do
              @stack.destroy!
            end
          end

          record_success_outcome

          if FeatureFlag.vexi.enabled?(:pull_request_stack_update_hydro_events, repository, default: false)
            GlobalInstrumenter.instrument("pull_request_stack.update", hydro_payload)
          end

          Success.new
        end
      end
    end
  end
end
