# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    module UpdatePulls
      class Service < BaseService
        class Success; end

        Result = T.type_alias { T.any(Success, Error) }
        ResultType = type_member { { fixed: Result } }

        sig { params(stack: Stack, pull_requests: T::Array[PullRequest], actor: User, log_context: T::Hash[String, String]).returns(Result) }
        def self.call(stack, pull_requests, actor:, log_context: {})
          new(stack, pull_requests, actor:, log_context:).call
        end

        sig { params(stack: Stack, pull_requests: T::Array[PullRequest], actor: User, log_context: T::Hash[String, String]).void }
        def initialize(stack, pull_requests, actor:, log_context: {})
          @stack = stack
          @pull_requests = pull_requests
          @actor = actor
          super(log_context:)
        end

        sig { override.returns(String) }
        def metric_key = "update_pulls"

        sig { override.returns(String) }
        def human_name = "Stack update pulls"

        sig { override.returns(T::Hash[String, T.untyped]) }
        def service_log_context = {
          "gh.repo.id" => @stack.repository_id,
          "gh.pull_request_stacks.id" => @stack.id,
          "gh.pull_request_stacks.update_pulls.size" => @pull_requests.size.to_s,
        }

        sig { override.returns(Result) }
        def perform
          current_entry_pr_ids = @stack.entries.order(position: :asc).pluck(:pull_request_id)
          submitted_pr_ids = @pull_requests.map(&:id)

          prefix = submitted_pr_ids.first(current_entry_pr_ids.size)
          if prefix != current_entry_pr_ids
            return logged_error_result(Error::FailureReason::StackContentsMismatch)
          end

          new_pulls = @pull_requests.drop(current_entry_pr_ids.size)
          if new_pulls.empty?
            record_success_outcome
            return Success.new
          end

          # Check none of the new PRs belong to other stacks
          stacked_pull_ids = PullRequests::StackEntry.where(
            repository_id: @stack.repository_id,
            pull_request_id: new_pulls.map(&:id),
          ).pluck(:pull_request_id).to_set
          already_stacked = new_pulls.select { stacked_pull_ids.include?(_1.id) }
          if already_stacked.any?
            return logged_error_result(Error::FailureReason::AlreadyStacked, pulls: already_stacked)
          end

          next_position = current_entry_pr_ids.size + 1

          # Validate chain: first new pull must chain from last current pull
          last_current_pull = @pull_requests[current_entry_pr_ids.size - 1]
          expected_base_ref = T.must(last_current_pull).head_ref

          new_pulls.each.with_index do |pull, index|
            if pull.repository_id != @stack.repository_id
              return logged_error_result(Error::FailureReason::MismatchedRepo)
            end
            if pull.cross_repo?
              return logged_error_result(Error::FailureReason::CrossRepo)
            end
            if pull.base_ref != expected_base_ref
              return logged_error_result(Error::FailureReason::NonLinear)
            end

            @stack.entries.build(
              pull_request: pull,
              repository_id: @stack.repository_id,
              position: next_position + index,
            )
            expected_base_ref = pull.head_ref
          end

          begin
            @stack.save!
          rescue ActiveRecord::RecordInvalid => exception
            logged_error_result(Error::FailureReason::ValidationFailed, exception:)
          else
            record_success_outcome
            GitHub.dogstats.distribution("pull_request_stacks.update_pulls_size_dist", @pull_requests.size)

            if FeatureFlag.vexi.enabled?(:pull_request_add_to_stack_hydro_events, @stack.repository, default: false)
              new_pulls.each do |pull|
                GlobalInstrumenter.instrument("pull_request.add_to_stack", {
                  actor: @actor,
                  issue: pull.issue,
                  pull_request: pull,
                  repository: pull.base_repository,
                  stack: @stack,
                })
              end
            end

            if FeatureFlag.vexi.enabled?(:pull_request_stack_update_hydro_events, @stack.repository, default: false)
              GlobalInstrumenter.instrument("pull_request_stack.update", {
                event_type: :UPDATED,
                stack_id: @stack.id,
                stack_number: @stack.number,
                stack_base_branch: @stack.base_ref,
                repository: @stack.repository,
                pull_requests_affected: new_pulls,
                stack_size: @pull_requests.size,
                actor: @actor,
              })
            end

            Success.new
          end
        end
      end
    end
  end
end
