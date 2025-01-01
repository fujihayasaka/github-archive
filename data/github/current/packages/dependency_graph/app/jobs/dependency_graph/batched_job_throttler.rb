# typed: strict
# frozen_string_literal: true

# Based on the original code from SecurityOverviewAnalytics::BatchedJobThrottler
#
# This module implements a mechanism to regulate the execution of batched jobs
# by introducing a delay before enqueuing the next batch. It supports configurable
# wait times between batches and optional jitter to add randomness to the delay.
#
# The wait time and jitter values are dynamically adjustable using actor-based
# percentage feature flags, enabling fine-grained control over job throttling behavior.
#
module DependencyGraph
  module BatchedJobThrottler
    extend T::Helpers
    abstract!

    requires_ancestor { BatchedJob }

    METRICS_PREFIX = "dependency_graph.jobs"

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
            "Next batch enqueued with wait.",
            "code.namespace": BatchedJobThrottler.name,
            "code.function": __method__,
            "gh.job.name": job.class.name,
            "gh.job.active_job_id": job.job_id,
            "gh.dependency_graph.batched_job_throttler.wait": wait,
            "gh.dependency_graph.batched_job_throttler.jitter": wait_jitter,
            "gh.dependency_graph.batched_job_throttler.wait_with_jitter": wait_with_jitter
          )
          GitHub.dogstats.distribution("#{METRICS_PREFIX}.batched_job_throttler.wait_with_jitter.dist", wait_with_jitter, tags: job.all_stats_tags)
        rescue => e # rubocop:todo Lint/RescueException
          # The rescue block is used to monitor possible errors from the tested block.
          # Instead of blocking the job, clearing the array and continue job execution if any error occurs.
          Failbot.report(e) rescue nil
        end

        block.call
      end
    end

    protected

    sig { returns(Float) }
    def wait_between_batches_in_seconds
      factor_flag = "dependency_graph_#{T.must(self.class.name).demodulize.underscore}_wait_between_batches_factor".to_sym
      # percentage_of_actors_value ranges from 0.01 to 100
      factor = T.let(FeatureFlag.vexi.percentage_of_actors_value_or_raise(factor_flag) * 1.0, T.any(Float, Integer)) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
      DEFAULT_WAIT_BETWEEN_BATCHES_IN_SECONDS * (factor <= 0 ? 1.0 : factor)
    end

    sig { returns(Float) }
    def wait_jitter
      flag = "dependency_graph_#{T.must(self.class.name).demodulize.underscore}_wait_jitter".to_sym
      # percentage_of_actors_value ranges from 0.01 to 100
      jitter = T.let(FeatureFlag.vexi.percentage_of_actors_value_or_raise(flag) * 1.0, Float) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
      jitter == 0 ? DEFAULT_JITTER : jitter
    end
  end
end
