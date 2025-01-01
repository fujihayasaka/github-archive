# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module BatchedJobThrottler
    extend T::Helpers
    abstract!

    requires_ancestor { BatchedJob }

    DEFAULT_WAIT_BETWEEN_BATCHES_IN_SECONDS = 1.0
    DEFAULT_JITTER = 1.0

    sig { params(base: Module).void }
    def self.included(base)
      T.unsafe(base).around_enqueue do |job, block|
        # Do nothing if job already enqueued with wait
        next block.call unless job.scheduled_at.nil?

        # Explicitly rescue and report errors for throttler logic
        begin
          wait = job.wait_between_batches_in_seconds
          wait_jitter = Kernel.rand * wait * job.wait_jitter
          wait_with_jitter = wait + wait_jitter
          job.set(wait: wait_with_jitter)

          GitHub.logger.info(
            "Batch enqueued with wait.",
            "code.namespace": BatchedJobThrottler.name,
            "code.function": __method__,
            "gh.job.name": job.class.name,
            "gh.job.active_job_id": job.job_id,
            "gh.security_overview_analytics.batched_job_throttler.wait": wait,
            "gh.security_overview_analytics.batched_job_throttler.wait_jitter": wait_jitter
          )
          GitHub.dogstats.distribution("security_overview_analytics.batched_job_throttler.wait_with_jitter.dist", wait_with_jitter, tags: job.all_stats_tags)
        rescue => e # rubocop:todo Lint/RescueException
          # The rescue block is used to monitor possible errors from the tested block.
          # Instead of blocking the job, clearing the array and continue job execution if any error occurs.
          Failbot.report(e)
        end

        block.call
      end
    end

    protected

    sig { returns(Float) }
    def wait_between_batches_in_seconds
      factor_flag = "security_overview_analytics_#{T.must(self.class.name).demodulize.underscore}_wait_between_batches_factor".to_sym
      # percentage_of_actors_value ranges from 0.01 to 100
      factor = T.let(FeatureFlag.vexi.percentage_of_actors_value_or_raise(factor_flag) * 1.0, T.any(Float, Integer)) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
      DEFAULT_WAIT_BETWEEN_BATCHES_IN_SECONDS * (factor <= 0 ? 1.0 : factor)
    end

    sig { returns(Float) }
    def wait_jitter
      flag = "security_overview_analytics_#{T.must(self.class.name).demodulize.underscore}_wait_jitter".to_sym
      # percentage_of_actors_value ranges from 0.01 to 100
      jitter = T.let(FeatureFlag.vexi.percentage_of_actors_value_or_raise(flag) * 1.0, Float) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
      jitter == 0 ? DEFAULT_JITTER : jitter
    end
  end
end
