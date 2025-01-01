# typed: strict
# frozen_string_literal: true

module PullRequests
  module ResolveMergeConflicts
    class Success < T::Struct
      const :orchestration, IOrchestration
    end

    class Error < T::Struct
      const :orchestration, IOrchestration
      const :error_message, T.nilable(String)
    end

    sig do
      params(
        pull_request: PullRequest,
        user: User,
        base_oid: String,
        expected_head_oid: String,
        resolve_conflicts: T::Hash[T.untyped, T.untyped],
        new_head_ref: T.nilable(String)
      ).returns(T.any(Success, Error))
    end
    def self.execute(pull_request:, user:, base_oid:, expected_head_oid:, resolve_conflicts:, new_head_ref:)
      orchestration = PullRequests::Orchestrations::ResolveConflicts.create(
        repository: pull_request.repository,
        pull_request:,
        user:,
        base_oid:,
        expected_head_oid:,
        new_head_ref:,
        resolve_conflicts:
      )

      begin
        orchestration.execute!
      rescue Orchestration::ValidationError
        error_msg = orchestration.errors.added?(:base, :duplicate) ? "Merge conflict already resolved." : orchestration.errors.full_messages.join(", ")
        Error.new(orchestration: orchestration, error_message: error_msg)
      else
        if orchestration.skipped? || orchestration.failed?
          Error.new(orchestration: orchestration, error_message: orchestration.error_message)
        else
          Success.new(orchestration: orchestration)
        end
      end
    end
  end
end
