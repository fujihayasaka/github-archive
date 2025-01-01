# typed: true
# frozen_string_literal: true

module GitHub
  module Aqueduct
    class TimedResqueImport
      extend T::Sig
      def initialize(redis: GitHub.job_coordination_redis, dry_run: true)
        @redis = redis
        @dry_run = dry_run
      end

      sig { returns(ImportResult) }
      def run
        result = ImportResult.new

        each_sorted_set_member(result) do |guid, schedule_at|
          raw_job_data = redis.hget(redis_payload_hash_key, guid)
          if raw_job_data.nil?
            result.record_failure(guid: guid, schedule_at: schedule_at, category: "missing payload")
            next
          end

          begin
            _, _, job_class_name, serialized_job, _ = GitHub::ZPack.decode(raw_job_data)

            if job_class_name == "GitHub::Jobs::RunPendingPlanChange"
              job_class_name = "RunPendingPlanChangeJob"
              pending_plan_change = ::Billing::PendingPlanChange.find_by(id: serialized_job.first)
              if pending_plan_change.nil?
                # The pending plan change doesn't exist any more - skip
                result.record_success(guid: guid, schedule_at: schedule_at, category: job_class_name)
                redis.hdel(redis_payload_hash_key, guid) unless dry_run?
                next
              end
              serialized_job = RunPendingPlanChangeJob.new(pending_plan_change).serialize
            end

            job_class = job_class_name.safe_constantize
            if job_class.nil?
              result.record_failure(guid: guid, schedule_at: schedule_at, category: "missing job (#{job_class_name})")
              next
            end

            unless dry_run?
              IntermediaryScheduledAqueductJob.perform_later(serialized_job.to_json, Time.at(schedule_at))
              redis.hdel(redis_payload_hash_key, guid)
            end
            result.record_success(guid: guid, schedule_at: schedule_at, category: job_class_name)
          rescue => ex # rubocop:todo Lint/GenericRescue
            result.record_failure(guid: guid, schedule_at: schedule_at, category: "#{ex.class.name}: #{ex.message}")
          end
        end

        result
      ensure
        result ||= ImportResult.new
        unless dry_run?
          result.failures.each do |job_result|
            redis.zadd(redis_sorted_set_key, job_result.schedule_at, job_result.guid)
          end
        end
      end

      private

      attr_reader :redis

      def each_sorted_set_member(result)
        if dry_run?
          GitHub.job_coordination_redis.zrangebyscore(redis_sorted_set_key, "-inf", "+inf", with_scores: true).each do |member|
            yield(*member)
          end
        else
          while (sorted_set_member = fetch_next_sorted_set_member(result)) && !result.general_failure? do
            yield(*sorted_set_member)
          end
        end
      end

      def dry_run?
        !!@dry_run
      end

      def redis_payload_hash_key
        @redis_payload_hash_key ||= "#{redis_key_prefix}timed-resque:jobs"
      end

      def redis_sorted_set_key
        @redis_sorted_set_key ||= "#{redis_key_prefix}timed-resque"
      end

      def redis_key_prefix
        @redis_key_prefix ||= "resque:#{GitHub.background_job_queue_prefix}"
      end

      def fetch_next_sorted_set_member(result)
        GitHub.job_coordination_redis.zpopmin(redis_sorted_set_key)
      rescue => error # rubocop:todo Lint/GenericRescue
        result.record_general_failure(error)
        nil
      end

      class ImportResult
        extend T::Sig

        sig { returns(T::Array[JobResult]) }
        attr_reader :successes
        sig { returns(T::Array[JobResult]) }
        attr_reader :failures
        sig { returns(T.any(T::Boolean, StandardError)) }
        attr_reader :general_failure

        delegate :count, to: :successes, prefix: true
        delegate :count, to: :failures, prefix: true

        def initialize
          @successes = []
          @failures = []
          @general_failure = false
        end

        def record_success(guid:, schedule_at:, category:)
          successes.push(JobResult.new(guid: guid, schedule_at: schedule_at, category: category))
        end

        def record_failure(guid:, schedule_at:, category:)
          failures.push(JobResult.new(guid: guid, schedule_at: schedule_at, category: category))
        end

        def record_general_failure(error)
          @general_failure = error
        end

        def general_failure?
          !!general_failure
        end
      end
      private_constant :ImportResult

      class JobResult
        attr_reader :guid, :schedule_at, :category

        def initialize(guid:, schedule_at:, category:)
          @guid = guid
          @schedule_at = schedule_at
          @category = category
        end
      end
      private_constant :JobResult
    end
  end
end
