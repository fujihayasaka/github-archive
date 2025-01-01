# typed: strict
# frozen_string_literal: true

module Repositories
  class PushApplicationJob < ApplicationJob
    extend T::Helpers
    include GitHub::Memoizer

    abstract!

    set_callback :perform, :before, :before_perform

    retry_on *Orchestration::RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 9

    class DiscardJob < StandardError; end
    discard_on DiscardJob do |error|
      GitHub.logger.info(
        "Discarding PushApplication job. Reason: #{error.message}",
        "code.namespace": "PushApplicationJob",
        "code.function": "discard_on",
        "exception.type": error.class.name
      )
    end

    protected

    sig { abstract.returns(Integer) }
    def repository_id; end

    sig { abstract.returns(Integer) }
    def push_id; end

    sig { returns(Repository) }
    memoize def repository
      # ActiveRecord::RecordNotFound is in Orchestration::RETRYABLE_ERRORS. We'll retry accordingly if the repository isn't found.
      Repositories::Public.get_active_or_deleted!(repository_id)
    end

    sig { params(name: Symbol).returns(T.untyped) }
    def get_named_job_argument(name)
      arguments.dig(0, name)
    end

    private

    sig { void }
    def before_perform
      skip_non_applicable_push
    end

    sig { void }
    def skip_non_applicable_push
      raise DiscardJob, "wiki (repo ID: #{repository_id})" if repository.path&.end_with?(".wiki.git")
      raise DiscardJob, "non-existent repo (repo ID: #{repository_id})" if (repository.deleted? && !repository.soft_creating?) || !repository.exists_on_disk?
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    memoize def logging_context
      super.merge({
        "gh.repo.id": repository_id,
        "gh.push.id": push_id
      })
    end
  end
end
