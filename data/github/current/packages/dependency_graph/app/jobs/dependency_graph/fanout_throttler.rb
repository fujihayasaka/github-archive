# typed: strict
# frozen_string_literal: true

# Based on the original code from SecurityOverviewAnalytics::FanoutThrottler
#
# This module implements a mechanism to regulate the execution of parent jobs by requeuing
# them until the queue depth of their associated fanout jobs falls below a defined threshold.
#
# This approach is particularly effective for GHES environments, which utilize aqueduct-lite,
# providing more reliable support for querying Job.queue_depth. In contrast, for dotcom/proxima,
# the reliability and performance of Job.queue_depth are known to be less consistent.
#
# Despite these limitations in dotcom/proxima, the mechanism is applied universally, as it is
# not expected to cause any adverse effects in those environments.
#
module DependencyGraph
  module FanoutThrottler
    extend T::Helpers
    abstract!

    MAX_ALLOWED_QUEUE_DEPTH = 10_000

    DEFAULT_ALLOWED_QUEUE_DEPTH = 1_000

    METRICS_PREFIX = "dependency_graph.jobs.fanout_throttler"

    requires_ancestor { ApplicationJob }

    sig { params(base: Module).void }
    def self.included(base)
      T.unsafe(base).around_perform do |job, block|
        job_queue_over_limit = T.let([], T::Array[String])
        set_fanout_depth = (job.fanout_depth * job.fanout_multiplier).to_i
        allowed_queue_depth = [set_fanout_depth, MAX_ALLOWED_QUEUE_DEPTH].min

        # Explicitly rescue and report errors from fanout job logic
        begin
          job.fanout_jobs.each do |fanout_job|
            queue_depth = fanout_job.queue_depth || 0
            GitHub.logger.info(
              "Checked fanout job queue depth",
              "code.namespace": FanoutThrottler.name,
              "code.function": __method__,
              "gh.dependency_graph.fanout_job.name": fanout_job.name,
              "gh.dependency_graph.fanout_job.queue_depth": queue_depth
            )
            GitHub.dogstats.distribution("#{METRICS_PREFIX}.queue_depth.dist", queue_depth,
              tags: job.all_stats_tags + [
                "fanout_job:#{fanout_job.queue_name}"
              ]
            )
            if queue_depth > allowed_queue_depth
              job_queue_over_limit << fanout_job.queue_name
              break
            end
          end
        rescue => e # rubocop:todo Lint/RescueException
          # The rescue block is used to monitor possible errors from the tested block.
          # Instead of blocking the job, clearing the array and continue job execution if any error occurs.
          job_queue_over_limit = []
          Failbot.report(e) rescue nil
        end

        if job_queue_over_limit.any?
          GitHub.logger.warn(
            "Fanout jobs queue depth above limit... throttling source job",
            "code.namespace": FanoutThrottler.name,
            "code.function": __method__,
            "gh.dependency_graph.allowed_queue_depth": allowed_queue_depth,
            "gh.dependency_graph.job_queues_over_limit": job_queue_over_limit.join(","),
          )
          GitHub.dogstats.increment("#{METRICS_PREFIX}.over_limit",
            tags: job.all_stats_tags + [
              *job_queue_over_limit.map { |q| "fanout_job:#{q}" }
            ]
          )
          # Delaying the job execution to allow fanout jobs to process
          job.class.set(wait: 5.minutes).perform_later(*job.arguments)
        else
          block.call
        end
      end
    end

    sig { abstract.returns(T::Array[T.class_of(ApplicationJob)]) }
    def fanout_jobs; end

    sig { returns(Integer) }
    def fanout_depth
      DEFAULT_ALLOWED_QUEUE_DEPTH
    end

    sig { returns(Float) }
    def fanout_multiplier
      flag = "dependency_graph_#{T.must(self.class.name).demodulize.underscore}_fanout_multiplier".to_sym
      # percentage_of_actors_value ranges from 0.01 to 100
      multiplier = T.let(FeatureFlag.vexi.percentage_of_actors_value_or_raise(flag) * 1.0, Float) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
      multiplier == 0 ? 1.0 : multiplier
    end
  end
end
