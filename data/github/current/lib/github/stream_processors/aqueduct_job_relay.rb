# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class AqueductJobRelay < BaseProcessor
      DEFAULT_GROUP_ID = "github_aqueduct_relay"
      DEFAULT_SUBSCRIBE_TO = /github.v1.AqueductJob\Z/

      options[:max_wait_time] = 0.2.seconds
      options[:session_timeout] = 30

      # By default processors will log the exception and move on. We'd like to block
      # so that we can find the problematic job and fix it (rather than dropping it).
      rescue_from(StandardError) { raise }

      set_callback :close, :after, :report_offsets

      def setup(filter: nil, **kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

        self.dead_letter_topic = "github.actions.v0.JobExecution.DeadLetter"

        @filter = filter
        @first_offsets = {}
        @last_offsets = {}
      end

      def batching?
        true
      end

      def process_with_consumer(batch, consumer) # rubocop:todo GitHub/DoNotOverrideProccessWithConsumerMethod
        process_batch(batch)
      end

      def process_batch(batch)
        jobs_with_options = []
        record_first_offset(batch.first)
        batch.each do |message|
          puts message.value if Rails.env.development?
          next if filter && !filter.call(message)
          begin
            job = to_job(message)
            metadata = {}
            metadata = GitHub::JSON.parse(message.value[:metadata]) if message.value[:metadata].present?
            deliver_at = Time.at(message.value[:deliver_at][:seconds]) if message.value[:deliver_at].present?
            headers = message.value[:headers]
          rescue => e # rubocop:todo Lint/GenericRescue
            # If deserialization fails, we report the failure and move on.
            report_deserialization_error(e, message)
            next
          end
          jobs_with_options << { job: job, options: { metadata: metadata, deliver_at: deliver_at, headers: headers } }
        end

        # we might have filtered out all the jobs or failed to deserialize.
        if jobs_with_options.empty?
          return
        end

        result = relay_jobs(jobs_with_options)
        if result.ok?
          record_last_offset(batch.last)
          handle_batch_result(result, batch)
          instrument_relay_stats_batch(jobs_with_options, batch)
        elsif !result.error.is_a?(GitHub::Aqueduct::Job::PayloadTooLargeError)
          report_errors(result.error, batch)
          GitHub.dogstats.increment("aqueduct_job_relay.error", tags: ["error:#{result.error.class}"])
          raise result.error
        else
          GitHub.dogstats.increment("aqueduct_job_relay.oversized_payload", tags: ["error:#{result.error.class}"])
        end
      end

      def handle_batch_result(result, batch)
        batch_response = result.value!
        # check if some jobs have failed and report the errors
        batch_response.each do |response|
          if !response[:error].blank?
            message = batch[response[:index]]
            job = to_job(message)
            error = StandardError.new(response[:error])
            report_error(error, message)
            GitHub.dogstats.increment("aqueduct_job_relay.error", tags: tags_for_job(job) + ["error:#{error}"])
            # enqueue it back to hydro for retry
            enqueue_to_hydro(message, GitHub.hydro_publisher)
          else
            # record successfully relayed jobs
            GitHub.dogstats.increment("aqueduct_job_relay.count")
          end
        end
      end

      private

      attr_reader :filter, :first_offsets, :last_offsets

      def record_first_offset(message)
        unless first_offsets[message.partition]
          first_offsets[message.partition] = message.offset

          unless Rails.env.test?
            Rails.logger.warn "Began processing partition #{message.partition} at offset #{message.offset}"
          end
        end
      end

      def record_last_offset(message)
        last_offsets[message.partition] = message.offset
      end

      def report_offsets
        last_offsets.each do |partition, offset|
          unless Rails.env.test?
            Rails.logger.warn "Finished processing partition #{partition} at offset #{offset}"
          end
        end
      end

      def relay_job(job, metadata:, deliver_at: nil, headers: nil)
        GitHub::Aqueduct::Job.enqueue_active_job(
          job,
          client: GitHub.aqueduct_gateway,
          metadata: metadata,
          deliver_at: deliver_at,
          headers: headers
        )
      end

      def relay_jobs(batch)
        GitHub::Aqueduct::Job.enqueue_active_jobs(batch)
      end

      def to_job(message)
        serialized_job = GitHub::JSON.parse(message.value[:serialized])
        job_class = serialized_job["job_class"].safe_constantize
        job = job_class.new
        job.deserialize(serialized_job)
        job
      end

      def instrument_relay_stats_batch(batch, messages)
        first_message = messages.first
        latency_ms = (Time.now.to_f - first_message.timestamp.to_f) * 1_000
        GitHub.dogstats.distribution("aqueduct_job_relay.latency", latency_ms.to_i)
        GitHub.dogstats.distribution("aqueduct_job_relay.batch_size", batch.size)
      end

      def report_deserialization_error(e, message)
        report_error(e, message)
        GitHub.dogstats.increment("aqueduct_job_relay.deserialize_error.count")
      end

      def tags_for_job(job)
        ["class:#{job.class.name.underscore}"]
      end

      def report_errors(error, batch)
        batch.each do |message|
          report_error(error, message)
        end
      end

      def enqueue_to_hydro(original_message, publisher)
        topic = GitHub.dynamic_lab? ? "review-lab.v1.AqueductJob" : "github.v1.AqueductJob"

        begin
          result = publisher.publish(original_message.value,
            schema: "github.v1.AqueductJob",
            topic: original_message.topic,
            # Publish to the original partition.
            partition: original_message.partition,
            topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }, # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
          )
        rescue => e # rubocop:todo Lint/GenericRescue
          return GitHub::Result.error(e)
        end

        result.success? ? GitHub::Result.new : GitHub::Result.error(result.error)
      end

      def report_error(error, message)
        Failbot.report(error, {
          hydro_msg_topic: message.topic,
          hydro_msg_partition: message.partition,
          hydro_msg_offset: message.offset,
        })
        GitHub.logger.error({
          :exception => error,
          "code.namespace" => "GitHub::StreamProcessors::AqueductJobRelay",
          "code.function" => "#relay_job",
          "messaging.source.name" => message.topic,
          "messaging.kafka.source.partition" => message.partition,
          "messaging.kafka.message.offset" => message.offset,
        })
      end
    end
  end
end
