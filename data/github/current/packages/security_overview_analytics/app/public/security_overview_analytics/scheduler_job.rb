# typed: strict
# frozen_string_literal: true

require_relative "../../../../security_products/app/models/security_center/k_v"

module SecurityOverviewAnalytics
  class SchedulerJob < ApplicationJob
    include GitHub::Memoizer

    queue_as :security_overview_analytics_job_scheduler

    schedule interval: 1.hour, scope: :global

    retry_on_dirty_exit

    class JobSchedule < T::Struct
      const :job, T.class_of(ApplicationJob)
      const :interval, ActiveSupport::Duration
    end

    sig { void }
    def perform
      job_schedules.each do |schedule|
        session_key = schedule.job.name
        if SecurityCenter::KV.store.exists(session_key).value { false }
          GitHub.dogstats.increment(
            "security_overview_analytics.scheduler_job.job_skipped",
            tags: self.all_stats_tags + ["job_class:#{session_key&.underscore}"]
          )
          next
        end

        # Schedule with random delay to avoid thundering herd
        schedule.job.set(wait: Kernel.rand(1..30).minutes).perform_later

        ActiveRecord::Base.connected_to(role: :writing) do
          SecurityCenter::KV.store.set(session_key, SecureRandom.uuid, expires: schedule.interval.from_now)
        end

        GitHub.dogstats.increment(
          "security_overview_analytics.scheduler_job.job_scheduled",
          tags: self.all_stats_tags + ["job_class:#{session_key&.underscore}"]
        )
      end
    end

    use_replicas \
      ApplicationRecord::SecurityOverviewAnalytics,

    protected

    sig { returns(T::Array[JobSchedule]) }
    memoize def job_schedules
      # Define a freezed list of job schedules in a method instead of constants
      # to avoid having to load module dependencies on jobs in timed job scripts.
      [
        JobSchedule.new(
          job: ::SecurityOverviewAnalytics::CalendarPopulationJob,
          interval: 1.day
        ),
        JobSchedule.new(
          job: ::SecurityOverviewAnalytics::RepositoryDataCleanupJob,
          interval: 7.days
        ),
        JobSchedule.new(
          job: ::SecurityOverviewAnalytics::DataRetentionEnforcementJob,
          interval: 7.days
        ),
        JobSchedule.new(
          job: ::SecurityOverviewAnalytics::RepositoryDataCompressionJob,
          interval: 60.days
        ),
      ].freeze
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "github-security-center"
      })
    end
  end
end
