# typed: true
# frozen_string_literal: true

require_relative "../jobs/job_enqueuing_proxy_job"

# Responsible for scheduling jobs with a TimerDaemon.
#
# Given the name of an `ApplicationJob` class and configuration options, scheudles
# the job to run at the configured interval.
#
# Also can be given a `ApplicationJob` class (or an object that responds to
# `schedule_options` and `enabled`), though this behavior is deprecated.
class JobScheduler
  # TimerDaemon instance
  attr_reader :timer_daemon

  # Public: Requires a `TimerDaemon` object to schedule jobs with.
  def initialize(timer_daemon)
    @timer_daemon = timer_daemon
  end

  # Public: Schedules the given job with the TimerDaemon instance.
  #
  # job - the job class or class name to be scheduled.
  # options - options for scheduling the job. Only used when a class name is given, else the options are taken from
  #   the class definition
  # options[:interval] - the interval to run the job at.
  # options[:scope] - the scope to run the job in.
  # options[:condition] - a proc that returns true if the job should be scheduled.
  #
  # Examples
  #
  #   scheduler = JobScheduler.new(timer_daemon)
  #   scheduler.schedule(ActiveJobClass)
  #   scheduler.schedule("ActiveJobClass", { interval: 1.hour, scope: "default", condition: -> { true } } }})
  #
  # Returns nothing.
  def schedule(job, options = {})
    if job.is_a? String
      schedule_with_job_name(job, **options)
    elsif job < ActiveJob::Base
      deprecated_schedule_with_job_class(job)
    else
      raise TypeError, "Scheduler#schedule requires ActiveJob class name, but was #{job}"
    end
  end

  private

  # Internal: Performs the job or enqueues the job to be run asynchronously (out
  # of band from the TimerDaemon).
  #
  # Returns nothing.
  def run_timer(job)
    timer_daemon.log("queued", { "gh.job.name" => job.name })

    if job < ActiveJob::Base
      DatabaseSelector.instance.track_writes(DatabaseSelector::LastOperations.empty) do
        job.perform_later
      end
    else
      raise TypeError, "Scheduler#run_timer requires ActiveJob class, but was #{job}"
    end
  end

  def run_timer_with_name(job_name)
    timer_daemon.log("queued", { "gh.job.name" => job_name })

    if job_name.is_a?(String)
      DatabaseSelector.instance.track_writes(DatabaseSelector::LastOperations.empty) do
        JobEnqueuingProxyJob.perform_later(job_name)
      end
    else
      raise TypeError, "Scheduler#run_timer_with_name requires ActiveJob class name, but was #{job_name}"
    end
  end

  def schedule_with_job_name(job_name, interval: nil, scope: :global, condition: nil)
    return unless interval
    enabled = condition.nil? || condition.call
    return unless enabled

    timer_daemon.schedule(job_name, interval, scope:) do |_timestamp|
      Failbot.push job: job_name
      run_timer_with_name job_name
    end
  rescue => boom # rubocop:todo Lint/GenericRescue
    Failbot.report(boom, timer: job_name, note: "#{job_name} not scheduled")
    raise if Rails.env.test? # rubocop:todo GitHub/DoNotBranchOnRailsEnv
  end

  def deprecated_schedule_with_job_class(job)
    return unless job.enabled?
    return unless job.schedule_options

    timer_daemon.schedule job.name, job.schedule_options[:interval], scope: job.schedule_options[:scope] do |_timestamp|
      Failbot.push job: job.name
      run_timer job
    end
  end
end
