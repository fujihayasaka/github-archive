# typed: true
# frozen_string_literal: true

module Search
  module Chatops
    class RepairIndex
      include ActionView::Helpers::DateHelper

      VALID_COMMANDS = Set.new %w[start stop status reset]

      # Create a new RepairIndex and execute the desired command.
      #
      # command    - The command to execute: list, start, stop, status, reset
      # index_name - The name of the search index to repair
      # args       - Array of args to pass to the command
      #
      # Returns the response message.
      def self.run(command:, index_name:, args: [])
        validate_command! command
        T.unsafe(self).new(index_name).public_send(command, *args)
      rescue ArgumentError => err
        err.message
      end

      # Validate that the given `command` is in our list of allowed repair
      # commands.
      #
      # Raises ArgumentError on unknown repair commands
      def self.validate_command!(command)
        return if VALID_COMMANDS.include? command.to_s
        raise ArgumentError, "Unknown repair command #{command.inspect}"
      end

      attr_reader :index_name

      # Create a new RepairIndexScript for the search index identified by name.
      #
      # index_name - The name of the search index to repair
      #
      def initialize(index_name)
        @index_name = index_name
      end

      #
      #
      def list
        raise ArgumentError, "not yet implemented"
      end

      # Start a repair worker. This method can be called multiple times to start
      # multiple workers to process the repair.
      #
      # count - The number of repair workers to start.
      #
      def start(count = 1)
        count = Integer(count)
        repair_job.enable.start(count)

        GitHub.dogstats.event \
          "Repair started for: #{index_name.inspect}",
          "Repair has been started for #{index_name.inspect} with #{count} workers using search chatops",
          tags: %W[search:ops action:repair-start from:chatops]

        "Repair has been started for #{index_name.inspect}"
      end

      # Stops the repair workers. Progress is saved, and the repair can be resumed
      # from the current progress point.
      def stop
        repair_job.disable

        GitHub.dogstats.event \
          "Repair stopped for: #{index_name.inspect}",
          "Repair has been stopped for #{index_name.inspect} using search chatops",
          tags: %W[search:ops action:repair-stop from:chatops]

        "Repair has been stopped for #{index_name.inspect}"
      end

      # Shows the current repair status.
      def status
        if repair_job.active?
          time = repair_job.estimated_completion_time
          time = time.nil? ? "no estimated completion time" : time.strftime("%Y-%m-%d %H:%M:%S %Z")
          "#{index_name} #{progress_bar} (#{time})\n- #{processed_records}"

        elsif repair_job.paused?
          "#{index_name} #{progress_bar} (paused)\n- #{processed_records}"

        elsif repair_job.finished?
          stats = repair_job.stats
          finished = stats[:finished].strftime("%Y-%m-%d %H:%M:%S %Z")
          "#{index_name} finished at #{finished}\n- #{processed_records(stats)}"

        else
          "No repair running for #{index_name.inspect}"
        end
      end

      # Reset the repair job. This will stop all repair workers and delete all
      # progress and stats for the repair job. Starting the repair again means that
      # the repair will have to start from the beginning.
      def reset
        if repair_job.active?
          return "Please stop the repair for #{index_name.inspect} and then reset"
        end
        repair_job.reset!

        GitHub.dogstats.event \
          "Repair reset for: #{index_name.inspect}",
          "Repair has been reset for #{index_name.inspect} using search chatops",
          tags: %W[search:ops action:repair-reset from:chatops]

        "Repair has been reset for #{index_name.inspect}!"
      end

      # Returns a progress bar string showing the current repair job progress.
      def progress_bar
        progress = repair_job.progress
        fraction = (progress > 0) ? progress / 100.0 : 0
        complete = (40 * fraction).round
        remaining = 40 - complete

        "[#{"#" * complete}#{" " * remaining}] %0.1f%%" % progress
      end

      # Returns a String describing the number of records processed thus far
      def processed_records(stats = repair_job.stats)
        started = stats[:started]
        finished = repair_job.finished? ? stats[:finished] : Time.now
        num_records = stats[:total]
        records = "record".pluralize(num_records)
        elapsed = distance_of_time_in_words(started, finished, include_seconds: true)

        "processed #{num_records} #{records} in #{elapsed}"
      end

      # Returns the repair job instance of the index name passed to the initializer.
      # If the index does not exist or there is not repair job for the index, then a
      # ArgumentError is raised.
      #
      # Returns a repair job instance.
      def repair_job
        return @repair_job if defined? @repair_job

        @repair_job = lookup_repair_job(index_name)
        if @repair_job.nil? || !@repair_job.index.exists?
          raise ArgumentError, "Unknown index: #{index_name.inspect}"
        end
        @repair_job
      end

      # Return a repair job for the given index name.
      #
      # name - The name of the index as a String
      #
      # Returns a repair job or `nil`
      def lookup_repair_job(name)
        repair_class = Elastomer.env.lookup_repair_job(name)

        return unless allowed_repair_class?(repair_class)

        repair_class.new(name) if repair_class < Elastomer::RepairJob
      rescue Elastomer::Error, ElastomerClient::Error
        nil
      end

      # Check if the repair job is allowed
      def allowed_repair_class?(repair_class)
        if repair_class.is_a?(RepairCodeSearchIndexJob)
          GitHub.use_elastomer_code_search?
        else
          true
        end
      end
    end
  end
end
