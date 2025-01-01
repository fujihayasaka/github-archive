# typed: true
# frozen_string_literal: true

module GitHub
  module Aqueduct
    # HydroMessageJobContext is responsible for enqueuing and executing HydroMessageJob jobs
    class HydroMessageJobContext < Job

      # Internal: the decoded hydro message
      attr_reader :decoded

      # Internal: the instance of the hydro message job.
      #
      # This is used by the QueryLogs execution hook so it's created during
      # initialize and not right before the job is performed.
      attr_reader :job_instance

      # Internal: hydro metadata
      attr_reader :kafka_cluster, :topic, :partition, :offset

      def initialize(...)
        super

        @job_class = HydroMessageJob.class_for_queue(job.queue)
        @queue = job.queue
        @decoded = Hydro::Decoding::ProtobufDecoder.decode(job.payload)

        # metadata for lifecycle callbacks:
        @kafka_cluster = job.headers["kafka-cluster"]
        @topic = job.headers["topic"]
        @partition = job.headers["partition"]&.to_i
        @offset = job.headers["offset"]&.to_i

        @job_instance = job_class.new(
          protobuf: @job.payload,
          headers: job.headers,
          queue: queue,
          schema: decoded.schema,
          timestamp: decoded.timestamp.to_i, # Rational to int
          timestamp_nano: decoded.timestamp, # Rational
          message: decoded.message,
        )
      end

      def execute_job
        @job_instance.perform_now
      end
    end
  end
end
