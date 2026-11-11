# frozen_string_literal: true

require "active_support/dependencies/autoload"
require "active_support/core_ext/module/attribute_accessors"

module ActiveJob
  module ScheduledJob
    extend ActiveSupport::Autoload

    autoload :Base
    autoload :JobScheduler

    # An instance of TimerDaemon that will be used to schedule jobs
    cattr_accessor :timer_daemon
    # An array of jobs that will be scheduled
    cattr_accessor :scheduled_jobs
    # A proc that will be called with the error and a hash of options when an
    # error is encountered. Defaults to printing the error and backtrace to
    # STDERR. For example: ->(error, job = nil) { Failbot.report(error) }
    cattr_accessor :error_reporter

    class << self
      def configure(&block)
        yield(self)

        raise "timer_daemon must be set" unless timer_daemon

        self.error_reporter ||= lambda { |error, opts = {}|
          $stderr.puts "ActiveJob::ScheduledJob error: #{error.class} - #{error.message}"
          $stderr.puts error.backtrace
        }

        scheduler = JobScheduler.new(timer_daemon, error_reporter)

        scheduled_jobs.each do |job|
          scheduler.schedule(job)
        end
      end

      def reset_config!
        self.timer_daemon = nil
        self.scheduled_jobs = []
        self.error_reporter = nil
      end
    end
  end
end
