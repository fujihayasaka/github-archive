# typed: strict
# frozen_string_literal: true

require_relative "../../models/security_center/k_v"

# SecurityCenter::DeadLetterJob is designed to rerun critical background jobs that
# stopped from unexpected reasons or exhausted retires.
#
# See ADR: https://github.com/github/security-center/blob/main/docs/engineering/adrs/0016-automatically-requeue-stopped-security-center-update-job.md
module SecurityCenter
  class DeadLetterJob < ApplicationJob
    extend T::Sig
    include GitHub::Memoizer

    queue_as :security_center_dead_letter
    schedule interval: 1.hour

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    locked_by timeout: 10.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

    MINIMUM_WAIT_TO_PERFORM_IN_SECONDS = T.let(60.0 * 60.0, Float)
    MAXIMUM_ENQUEUE_WAIT = T.let(15.minutes.to_f, Float)

    class CacheData < T::Struct
      extend T::Sig
      include GitHub::Memoizer

      CACHE_PREFIX = "security-center-dlq:"
      CACHE_KEY_TEMPLATE = T.let("#{CACHE_PREFIX}%{target_job_type}:%{target_job_inputs}", String)
      CACHE_DURATION = T.let(24.hours, ActiveSupport::Duration)
      STATE_SCHEDULED = :scheduled
      STATE_PERFORMED = :performed

      prop :state, Symbol
      const :job_class, T.class_of(ApplicationJob)
      const :arguments, T::Hash[Symbol, T.untyped]
      const :scheduled_time, Float

      sig { returns(String) }
      memoize def to_json
        JSON.generate(self.as_json)
      end

      sig { returns(String) }
      memoize def key
        CACHE_KEY_TEMPLATE % {
          target_job_type: job_class.name,
          target_job_inputs: arguments
        }
      end

      sig { returns(T::Boolean) }
      def performed?
        state == STATE_PERFORMED
      end

      sig { returns(T::Boolean) }
      def exists?
        SecurityCenter::KV.store.exists(key).value { false }
      end

      sig { void }
      def save!
        ActiveRecord::Base.connected_to(role: :writing) do
          SecurityCenter::KV.store.set(key, to_json, expires: CACHE_DURATION.from_now)
        end
      end

      sig { params(input: String).returns(T.nilable(CacheData)) }
      def self.from_json(input)
        return nil if input.blank?

        data = JSON.parse(input)&.symbolize_keys
        return nil if data.blank?

        state = data[:state]&.to_sym
        return nil if state.blank?
        return nil unless [STATE_PERFORMED, STATE_SCHEDULED].include?(state)

        job_class = data[:job_class]&.constantize
        return nil if job_class.blank?
        return nil unless job_class < ApplicationJob

        arguments = data[:arguments]
        return nil if arguments.blank?
        return nil unless arguments.instance_of?(Hash)
        arguments.symbolize_keys!

        scheduled_time = data[:scheduled_time]
        return nil if scheduled_time.blank?
        return nil unless scheduled_time.instance_of?(Float)

        CacheData.new(state: state, job_class: job_class, arguments: arguments, scheduled_time: scheduled_time)
      rescue JSON::ParserError, NameError
        nil
      end
    end

    sig do
      params(
        job_class: T.class_of(ApplicationJob),
        arguments: T::Hash[Symbol, T.untyped],
        reason:  T.any(T.nilable(String), T.nilable(StandardError))
      ).void
    end
    def self.schedule_for_retry(job_class:, arguments: {}, reason: nil)
      cache_data = CacheData.new(
        state: CacheData::STATE_SCHEDULED,
        job_class: job_class,
        arguments: arguments,
        scheduled_time: Time.now.to_f
      )
      if cache_data.exists?
        GitHub.logger.info(
          "Scheduled job exists",
          "code.namespace": self.name,
          "code.function": __method__,
          "gh.security_center.dlq.cache_key": cache_data.key,
          "gh.security_center.dlq.cache_data": cache_data.to_json,
          "gh.security_center.dlq.reason": reason,
        )
        GitHub.dogstats.increment("security_center.dead_letter_job.scheduled_job_exists", tags: [
          "type:#{job_class.name&.underscore}",
          "reason:#{reason&.to_s&.underscore}",
        ])
      end

      cache_data.save!

      GitHub.logger.info(
        "Job scheduled for retry",
        "code.namespace": self.name,
        "code.function": __method__,
        "gh.security_center.dlq.cache_key": cache_data.key,
        "gh.security_center.dlq.cache_data": cache_data.to_json,
        "gh.security_center.dlq.reason": reason,
      )
      GitHub.dogstats.increment("security_center.dead_letter_job.job_scheduled_for_retry", tags: [
        "type:#{job_class.name&.underscore}",
        "reason:#{reason&.to_s&.underscore}",
      ])
    end

    sig { void }
    def perform
      if scheduled_jobs.present?
        now = Time.now.to_f
        scheduled_jobs.each do |job_to_run|
          if (now - job_to_run.scheduled_time) > MINIMUM_WAIT_TO_PERFORM_IN_SECONDS
            random_wait = jitter
            job_to_run.job_class.set(wait: random_wait).perform_later(**job_to_run.arguments)
            job_to_run.state = CacheData::STATE_PERFORMED
            job_to_run.save!

            GitHub.logger.info(
              "Scheduled job performed.",
              "code.namespace": self.class.name,
              "code.function": __method__,
              "gh.security_center.dlq.jitter": random_wait,
              "gh.security_center.dlq.cache_key": job_to_run.key,
              "gh.security_center.dlq.cache_data": job_to_run.to_json,
            )
            GitHub.dogstats.increment(
              "security_center.dead_letter_job.scheduled_job_performed",
              tags: all_stats_tags + ["type:#{job_to_run.job_class.name&.underscore}"]
            )
          else
            GitHub.logger.info(
              "Scheduled job skipped due to minimum wait.",
              "code.namespace": self.class.name,
              "code.function": __method__,
              "gh.security_center.dlq.minimum_wait_in_secs": MINIMUM_WAIT_TO_PERFORM_IN_SECONDS,
              "gh.security_center.dlq.cache_key": job_to_run.key,
              "gh.security_center.dlq.cache_data": job_to_run.to_json,
            )
            GitHub.dogstats.increment(
              "security_center.dead_letter_job.scheduled_job_skipped",
              tags: all_stats_tags + ["type:#{job_to_run.job_class.name&.underscore}"]
            )
          end
        end
      else
        GitHub.logger.info(
          "No scheduled job found.",
          "code.namespace": self.class.name,
          "code.function": __method__,
        )
        GitHub.dogstats.increment("security_center.dead_letter_job.no_scheduled_job_found", tags: all_stats_tags)
      end
    end

    protected

    sig { returns(T::Array[CacheData]) }
    memoize def scheduled_jobs
      all_jobs = SecurityCenter::KV.store.mget_prefix(CacheData::CACHE_PREFIX).value { {} }
      all_jobs.each_with_object([]) do |(key, data), scheduled_jobs|
        parsed_data = CacheData.from_json(data)
        if parsed_data.nil?
          GitHub.logger.info(
            "Failed to parse cache data.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_center.dlq.cache_key": key,
            "gh.security_center.dlq.cache_data": data,
          )
          GitHub.dogstats.increment("security_center.dead_letter_job.cannot_parse_cache_data", tags: all_stats_tags)
        else
          GitHub.logger.info(
            "Cache data parsed successfully.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_center.dlq.cache_key": key,
            "gh.security_center.dlq.cache_data": data,
          )
          scheduled_jobs << parsed_data unless parsed_data.performed?
        end
      end
    end

    sig { returns(ActiveSupport::Duration) }
    def jitter
      SecureRandom.rand(MAXIMUM_ENQUEUE_WAIT).seconds
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "github-security-center"
      })
    end
  end
end
