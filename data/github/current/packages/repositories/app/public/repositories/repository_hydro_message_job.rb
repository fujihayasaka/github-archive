# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Repositories
  class RepositoryHydroMessageJob < HydroMessageJob
    set_callback :perform, :before, :set_repository_context

    retry_on(*Orchestration::RETRYABLE_ERRORS, delay: :polynomially_longer, max_retries: Orchestration::MAX_ATTEMPTS + 1)

    attr_reader :repository_id, :request_id, :actor_id

    def initialize(protobuf:, headers:, schema:, timestamp:, timestamp_nano:, message:, queue:)
      super

      @repository_id, @request_id = message.values_at(
        :repository_id,
        :request_id
      )

      @actor_id = case message[:actor_id]
      when Integer
        message[:actor_id]
      when Hash
        message[:actor_id][:value] if message[:actor_id].key?(:value)
      end
    end

    protected

    sig { returns(Repository) }
    def repository
      return @repository if defined?(@repository)
      @repository = Repositories::Public.get_active_or_deleted!(repository_id)
    end

    def logging_context
      super.merge({
        "gh.repo.id": repository_id,
        "gh.request_id": request_id
      })
    end

    def set_repository_context
      GitHub.context.push(repository_id:, request_id:)
      Failbot.push("gh.repo.id": repository_id, "gh.request_id": request_id)
    end
  end
end
