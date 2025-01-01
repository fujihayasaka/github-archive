# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module FanoutThrottler
    extend T::Sig
    extend T::Helpers
    abstract!

    MAX_ALLOWED_QUEUE_DEPTH = 1000

    requires_ancestor { ApplicationJob }

    sig { params(base: Module).void }
    def self.included(base)
      T.unsafe(base).around_perform do |job, block|
        # GHES uses aqueduct-lite which has better support for calling queue_depth
        # For dotcom/proxima, according to the owning team, it is unreliable and doesn't perform well.
        # Since we can absorb a significant amount of jobs on dotcom/proxima, we skip fanout throttling.
        next block.call unless GitHub.enterprise?

        job_queue_over_limit = T.let([], T::Array[String])

        # Explicitly rescue and report errors from fanout job logic
        begin
          job.fanout_jobs.each do |fanout_job|
            queue_depth = fanout_job.queue_depth || 0
            GitHub.logger.info(
              "Fanout job queue depth recorded.",
              "code.namespace": FanoutThrottler.name,
              "code.function": __method__,
              "gh.security_overview_analytics.fanout_job.name": fanout_job.name,
              "gh.security_overview_analytics.fanout_job.queue_depth": queue_depth
            )
            GitHub.dogstats.distribution("security_overview_analytics.fanout_throttler.queue_depth.dist", queue_depth, tags: job.all_stats_tags)

            if queue_depth > MAX_ALLOWED_QUEUE_DEPTH
              job_queue_over_limit << fanout_job.queue_name
              break
            end
          end
        rescue => e # rubocop:todo Lint/GenericRescue
          # The rescue block is used to monitor possible errors from the tested block.
          # Instead of blocking the job, clearing the array and continue job execution if any error occurs.
          job_queue_over_limit = []
          Failbot.report(e)
        end

        if job_queue_over_limit.any?
          GitHub.logger.info(
            "Job fanout is being throttled.",
            "code.namespace": FanoutThrottler.name,
            "code.function": __method__,
            "gh.security_overview_analytics.max_allowed_queue_depth": MAX_ALLOWED_QUEUE_DEPTH,
            "gh.security_overview_analytics.job_queues_over_limit": job_queue_over_limit.join(","),
          )
          GitHub.dogstats.increment("security_overview_analytics.fanout_throttler.throttle", tags: job.all_stats_tags + [
            *job_queue_over_limit.map { |q| "job_queue_over_limit:#{q}" }
          ])
          job.class.perform_later(*job.arguments)
        else
          block.call
        end
      end
    end

    sig { abstract.returns(T::Array[T.class_of(ApplicationJob)]) }
    def fanout_jobs; end
  end
end
