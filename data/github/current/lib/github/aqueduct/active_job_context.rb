# typed: true
# frozen_string_literal: true

# GitHub::Aqueduct::Job handles enqueuing and executing jobs via aqueduct.
module GitHub
  module Aqueduct
    # ActiveJobContext is responsible for enqueuing and executing ActiveJob jobs
    class ActiveJobContext < Job

      # Internal: a payload pointer, if present in the decoded job
      attr_reader :pointer

      # The job payload.
      attr_reader :payload

      # Metadata associated with this job.
      attr_reader :metadata

      def initialize(...)
        super

        decoded = GitHub::JSON.decode(job.payload)

        @payload = if (@pointer = decoded["pointer"])
          PayloadPointer.fetch(pointer)
        else
          decoded.fetch("payload")
        end

        @queue = decoded.fetch("queue")
        @job_class = decoded.fetch("job_class")
        @metadata = decoded.fetch("metadata", {})
        @headers = job.headers
      end

      def execute_job
        ActiveJob::Base.execute(payload)

        if pointer
          begin
            PayloadPointer.cleanup(pointer)
          rescue => e # rubocop:todo Lint/GenericRescue
            # Swallow pointer cleanup exceptions because the job has already executed.
            Failbot.report(e, { app: "github-aqueduct" })
          end
        end
      end

    end
  end
end
