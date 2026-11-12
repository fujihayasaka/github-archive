# frozen_string_literal: true

require "active_support/callbacks"

module ActiveJob
  module ScheduledJob
    class JobScheduler
      # TimerDaemon instance
      attr_reader :timer_daemon
      # Error reporter proc
      attr_reader :error_reporter

      # Public: Requires a `TimerDaemon` object to schedule jobs with.
      def initialize(timer_daemon, error_reporter)
        @timer_daemon = timer_daemon
        @error_reporter = error_reporter
      end

      # Public: Schedules the given job with the TimerDaemon instance.
      #
      # job - the job class to be scheduled.
      #
      # Returns nothing.
      def schedule(job)
        unless job < ActiveJob::Base
          raise TypeError, "JobScheduler#schedule requires ActiveJob class, but was #{job}"
        end

        return unless job.enabled?
        return unless schedule = job.schedule_options

        timer_daemon.schedule(job.name, job.schedule_options[:interval], scope: job.schedule_options[:scope]) do |_timestamp|
          run_timer job
        end
      rescue StandardError => error
        error_reporter.call(error, timer: job.name, note: "#{job.name} failed to schedule")
      end

      # Internal: Performs the job or enqueues the job to be run asynchronously (out
      # of band from the TimerDaemon).
      #
      # Returns nothing.
      def run_timer(job)
        timer_daemon.log(scheduler: "queued", job_name: job.name)

        if job < ActiveJob::Base
          job.perform_later
        else
          raise TypeError, "JobScheduler#run_timer requires ActiveJob class, but was #{job}"
        end
      end
    end
  end
end
