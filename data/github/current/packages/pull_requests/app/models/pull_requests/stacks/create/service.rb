# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    module Create
      class Service < BaseService
        Result = T.type_alias { T.any(Stack, Error) }
        ResultType = type_member { { fixed: Result } }

        sig { params(pull_requests: T::Array[PullRequest], actor: User, log_context: T::Hash[String, String]).returns(Result) }
        def self.call(pull_requests, actor:, log_context: {})
          new(pull_requests, actor:, log_context:).call
        end

        sig { params(pull_requests: T::Array[PullRequest], actor: User, log_context: T::Hash[String, String]).void }
        def initialize(pull_requests, actor:, log_context:)
          @pull_requests = pull_requests
          @actor = actor
          super(log_context:)
        end

        sig { override.returns(String) }
        def metric_key = "creation"

        sig { override.returns(String) }
        def human_name = "Stack creation"

        sig { override.returns(T::Hash[String, T.untyped]) }
        def service_log_context = {
          "gh.pull_request_stacks.creation.size" => @pull_requests.size.to_s,
        }

        sig { override.returns(Result) }
        def perform
          pulls = @pull_requests

          if pulls.size < 2
            return logged_error_result(Error::FailureReason::TooSmall)
          end

          first_pull = T.must(pulls.first)
          repository = T.must(first_pull.repository)

          stacked_pull_ids = PullRequests::StackEntry.where(
            repository_id: repository.id,
            pull_request_id: pulls.map(&:id),
          ).pluck(:pull_request_id).to_set
          already_stacked = pulls.select { stacked_pull_ids.include?(_1.id) }
          if already_stacked.any?
            return logged_error_result(Error::FailureReason::AlreadyStacked, pulls: already_stacked)
          end

          stack = Stack.new
          stack.repository = repository
          stack.base_ref = first_pull.base_ref

          expected_base_ref = stack.base_ref
          pulls.each.with_index do |pull, index|
            if pull.repository_id != repository.id
              return logged_error_result(Error::FailureReason::MismatchedRepo)
            end
            if pull.cross_repo?
              return logged_error_result(Error::FailureReason::CrossRepo)
            end
            if pull.base_ref != expected_base_ref
              return logged_error_result(Error::FailureReason::NonLinear)
            end

            stack.entries.build(
              pull_request: pull,
              repository:,
              position: index + 1,
            )
            expected_base_ref = pull.head_ref
          end

          stack.number = generate_number(repository)
          begin
            stack.save!
          rescue ActiveRecord::RecordInvalid => exception
            return logged_error_result(Error::FailureReason::ValidationFailed, exception:)
          end

          record_success_outcome(extra_log: { "gh.pull_request_stacks.id" => stack.id })
          GitHub.dogstats.distribution("pull_request_stacks.creation_size_dist", @pull_requests.size)

          if FeatureFlag.vexi.enabled?(:pull_request_add_to_stack_hydro_events, repository, default: false)
            @pull_requests.each do |pull|
              GlobalInstrumenter.instrument("pull_request.add_to_stack", {
                actor: @actor,
                issue: pull.issue,
                pull_request: pull,
                repository: pull.base_repository,
                stack: stack,
              })
            end
          end

          if FeatureFlag.vexi.enabled?(:pull_request_stack_update_hydro_events, repository, default: false)
            GlobalInstrumenter.instrument("pull_request_stack.update", {
              event_type: :CREATED,
              stack_id: stack.id,
              stack_number: stack.number,
              stack_base_branch: stack.base_ref,
              repository: repository,
              pull_requests_affected: @pull_requests,
              stack_size: @pull_requests.size,
              actor: @actor,
            })
          end

          stack
        end

        private

        sig { params(repository: ::Repository).returns(Integer) }
        def generate_number(repository)
          # NOTE: Normally we'd explicitly check if a sequence exists before
          # using it, but in this context the repo must already have multiple
          # PRs in order to create a stack, and therefore it must have a
          # sequence.
          ActiveRecord::Base.connected_to(role: :writing) do
            Sequence.next(repository)
          end
        end
      end
    end
  end
end
