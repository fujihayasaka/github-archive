# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module LifecycleEventHandler
    extend T::Helpers
    abstract!

    # This mixin can only be included in classes that extend HydroMesageJob.
    requires_ancestor { HydroMessageJob }

    RETRYABLE_ERRORS = T.let([
      ::Repository::SecurityCenterDependency::UnknownSecurityFeatureStatusError,
      ActiveRecord::RecordNotFound, # replication lag
      Freno::Error, # All things Freno
      GitRPC::NetworkError, # Transient network errors with git service (not "git network")
      *Resiliency::Response::UnavailableExceptions, # DB unavailable
    ], T::Array[T.class_of(StandardError)])

    class RepositoryConfigNotFound < StandardError; end

    sig { params(base: Module).void }
    def self.included(base)
      # Because this can only be included on classes that extend HydroMessageJob,
      # we know that we can invoke `retry_on` here.
      T.unsafe(base).retry_on(*RETRYABLE_ERRORS, delay: :polynomially_longer)

      T.unsafe(base).retry_on(RepositoryConfigNotFound, delay: :polynomially_longer) do |job, _|
        job = T.cast(job, LifecycleEventHandler)
        # If we don't find the config after retries, reconcile the repo to ensure we have the latest data
        RepositoryReconciliationJob.perform_later(repository_id: job.repository_id, source_event: "security_center.missing_repo_config")
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: job.all_stats_tags + ["cause:missing_repo_config"])
        GitHub.logger.warn(
          "Failed to find the repository config to update. Scheduling reconciliation.",
          "code.namespace": self.class.name,
          "code.function": __method__,
        )
      end

    end

    sig { abstract.returns(Integer) }
    def repository_id; end

    private

    sig { void }
    def instrument_repository_updated
      elapsed_time = (Time.now.to_f - timestamp) * 1_000

      GitHub.dogstats.distribution("security_center.repository_updated.dist", elapsed_time, tags: all_stats_tags)
      GitHub.logger.info(
        "Repository updated",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_center.repository_update.elapsed_time": elapsed_time,
      )
    end
  end
end
