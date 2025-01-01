# typed: strict
# frozen_string_literal: true

module PullRequests
  module ChangeBase
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
        new_base: String,
      ).returns(T.any(Success, Error))
    end
    def self.execute(pull_request:, user:, new_base:)
      data = {
        user_id: user.id, new_base:,
      }
      orchestration = PullRequests::Orchestrations::ChangeBase.create(repository: pull_request.repository, pull_request:, data:)
      begin
        orchestration.execute!
      rescue Orchestration::ValidationError
        error_msg = orchestration.errors.added?(:base, :duplicate) ? "Base already being changed." : orchestration.errors.full_messages.join(", ")
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
