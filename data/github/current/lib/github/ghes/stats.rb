# typed: true
# frozen_string_literal: true

require "json"

module GitHub::GHES
  # Module for emitting structured events for migration statuses
  module Stats
    extend ActiveSupport::Concern

    included do
      prepend GitHub::GHES::PrependMethods
    end


    # wrap the migration with a block that will emit events to a file
    def self.wrap(version, name, direction)
      # Do not proceed if we are not provided a block
      if false == block_given?
        return nil
      end

      file = File.open(ENV.fetch("MIGRATION_EVENTS_FILE", "/dev/null"), "a")
      EventWriter.open(file) do |writer|
        writer.write(create_migrate_start_event(version, name, Time.now))
        begin
          if direction == :up
            ENV["TRANSITION_ID"] = version.to_s
          end
          # call the original migration
          yield
        rescue StandardError => se
          # if the migration fails, print the error to stderr, create an error event and re-raise
          $stderr.puts "Error running migration: #{se}"
          writer.write(create_error_event(se, Time.now, version, name))
          raise
        end
        writer.write(create_migrate_end_event(version, name, Time.now))
      end
    end

    # Pure functions for creating structured events with no state to operate on
    def self.create_migrate_start_event(version, name, start_time)
      {
        version: version,
        name: name,
        start_time: start_time,
        event_version: "v1",
        event_type: "migrate_start"
      }
    end

    def self.create_migrate_end_event(version, name, end_time)
      {
        version: version,
        name: name,
        end_time: end_time,
        event_version: "v1",
        event_type: "migrate_end"
      }
    end

    def self.create_structured_list_of_migration_statuses(migration_status)
      if migration_status.nil?
        return []
      end

      migration_status.map do |l|
        { "status" => l[0], "version" => l[1], "description" => l[2] }
      end
    end

    def self.create_error_event(error, time, version = nil, name = nil)
      {
        event_version: "v1",
        event_type: "migrate_error",
        message: error ? error.message : nil,
        event_time: time,
        version: version,
        name: name
      }
    end

    class EventWriter
      # Initialize with an IO object to write to
      def initialize(output_stream)
        @output_stream = output_stream
      end

      def write(event)
        @output_stream.puts JSON.dump(event)
      end

      def close
        @output_stream.close
      end

      # Class method to implement the block pattern
      def self.open(file, &block)
        writer = EventWriter.new(file)

        begin
          # Yield the writer to the block
          yield writer
        ensure
          # Close the file after the block is executed
          writer.close
        end
      end
    end

    class NullEventWriter < EventWriter
      def write(event)
        # do nothing
      end

      def close
        # do nothing
      end
    end
  end

  module PrependMethods
    extend T::Helpers

    requires_ancestor do
      ActiveRecord::Migration
    end

    def migrate(direction)
      Stats.wrap(self.version, self.name, direction) { super }
    end

  end
end
