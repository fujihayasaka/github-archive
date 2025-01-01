# typed: strict
# frozen_string_literal: true

module PullRequests
  module UpdateBranch
    extend T::Sig

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
        update_method: String,
        base_oid: T.nilable(String),
        expected_head_oid: T.nilable(String),
        resolve_conflicts: T.nilable(T::Hash[T.untyped, T.untyped]),
      ).returns(T.any(Success, Error))
    end
    def self.execute(pull_request:, user:, update_method:, base_oid: nil, expected_head_oid: nil, resolve_conflicts: nil)
      data = {
        user_id: user.id, update_method:, expected_head_oid:, base_oid:, resolve_conflicts:
      }
      orchestration = PullRequests::Orchestrations::UpdateBranch.create(repository: pull_request.repository, pull_request:, data:)
      begin
        orchestration.execute!

        if orchestration.failed?
          Error.new(orchestration: orchestration, error_message: orchestration.error_message)
        end

      rescue Orchestration::ValidationError
        error_msg = orchestration.errors.added?(:base, :duplicate) ? "branch update already in progress" : orchestration.errors.full_messages.join(", ")
        Error.new(orchestration: orchestration, error_message: error_msg)
      else
        Success.new(orchestration: orchestration)
      end
    end
  end
end
