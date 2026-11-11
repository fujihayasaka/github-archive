# typed: strict
# frozen_string_literal: true

module Exporter
  # Service for writing serialized model data to files with automatic rotation.
  #
  # This service accumulates records in memory and writes them to files when
  # the batch size is reached, using the naming convention:
  # <prefix>_<iteration>.json (e.g., "users_000000.json")
  #
  # Example usage:
  #   writer = ModelFileWriter.new(working_dir: "/tmp/exports", prefix: "users")
  #   writer.write({"id" => 1, "login" => "octocat"})
  #   writer.write({"id" => 2, "login" => "hubot"})
  #   writer.finalize
  class ModelFileWriter
    # Maximum number of records per file before rotating to a new file
    BATCH_SIZE = 100

    sig { params(working_dir: String, prefix: String).void }
    def initialize(working_dir:, prefix:)
      @working_dir = working_dir
      @prefix = prefix
      @current_batch = T.let([], T::Array[T::Hash[String, T.untyped]])
      @iteration = T.let(0, Integer)
    end

    # Add a record to the current batch. Automatically writes and rotates
    # to a new file when BATCH_SIZE is reached.
    #
    # record - Hash containing serialized model data
    #
    # Returns nothing.
    sig { params(record: T::Hash[String, T.untyped]).void }
    def write(record)
      @current_batch << record

      # Write current batch when we reach the limit
      if @current_batch.size >= BATCH_SIZE
        flush_current_batch
      end
    end

    # Finalize writing by flushing any remaining records.
    #
    # Returns nothing.
    sig { void }
    def finalize
      flush_current_batch unless @current_batch.empty?
    end

    private

    # Write the current batch to a file and reset for the next batch.
    sig { void }
    def flush_current_batch
      return if @current_batch.empty?

      # Generate filename: <prefix>_<iteration>.json
      iteration_str = @iteration.to_s.rjust(6, "0")
      filename = "#{@prefix}_#{iteration_str}.json"
      file_path = File.join(@working_dir, filename)

      # Write the batch as a JSON array
      File.open(file_path, "w") do |file|
        file.write(::JSON.pretty_generate(@current_batch.as_json))
      end

      # Reset for next batch
      @current_batch = []
      @iteration += 1
    end
  end
end
