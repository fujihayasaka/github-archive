# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module DeadLetter
      class CLI < Thor
        DEFAULT_GROUP_ID = "hydro_dead_letter_cli_#{SecureRandom.hex(4)}"
        DEFAULT_LIMIT = 10

        desc "list-topics", "List known dead-letter topics"
        def list_topics
          table = [["Processor Class", "Dead Letter Topic"], ["-" * 15, "-" * 17]]
          table += stream_processors.map do |processor_class|
            processor = processor_class.new
            [
              processor_class.name.sub(/\AGitHub::StreamProcessors::/, ""),
              processor.dead_letter_topic.presence || set_color("<none>", :yellow),
            ]
          end

          print_table table
        end

        desc "show TOPIC [TOPIC...]", "Show messages from a dead-letter topic"
        option :group, default: DEFAULT_GROUP_ID, desc: "Consumer group identifier to use for fetching Hydro messages"
        option :limit, type: :numeric, desc: "Maximum number of messages to show at a time (default 10)"
        option :min_offset, type: :numeric, desc: "Starting Kafka offset to fetch"
        option :max_offset, type: :numeric, desc: "Ending Kafka offset to fetch"
        option :after, type: :string, desc: "Starting date/time of messages to fetch"
        option :before, type: :string, desc: "Ending date/time of messages to fetch"
        option :payload, type: :string, desc: "Payload content to search for"
        option :error, type: :string, desc: "Error content to search for"
        def show(*topics)
          topics.each do |topic|
            iterator = TopicIterator.new(
              topic: topic,
              group: options[:group],
              shell: shell,
              stream_processors: stream_processors,
              limit: options[:limit] || DEFAULT_LIMIT,
              min_offset: options[:min_offset],
              max_offset: options[:max_offset],
              after: options[:after],
              before: options[:before],
              payload_pattern: options[:payload],
              error_pattern: options[:error],
            )
            iterator.show_messages
          end
        end

        desc "replay TOPIC [TOPIC...]", "Replay messages from a dead-letter topic"
        option :group, default: DEFAULT_GROUP_ID, desc: "Consumer group identifier to use for fetching Hydro messages"
        option :limit, type: :numeric, desc: "Maximum number of messages to show at a time (default 10)"
        option :min_offset, type: :numeric, desc: "Starting Kafka offset to fetch"
        option :max_offset, type: :numeric, desc: "Ending Kafka offset to fetch"
        option :after, type: :string, desc: "Starting date/time of messages to fetch"
        option :before, type: :string, desc: "Ending date/time of messages to fetch"
        option :payload, type: :string, desc: "Payload content to search for"
        option :error, type: :string, desc: "Error content to search for"
        option :yes, aliases: [:y], type: :boolean, desc: "Replay messages without prompting for confirmation"
        option :processor, type: :string, desc: "Fully-qualified class name of the Hydro processor to use for replaying messages"
        def replay(*topics)
          if options[:yes] && !(options[:min_offset] && options[:max_offset])
            say "#{set_color('ERROR:', :red, :bold)} The option --yes requires --min-offset and --max-offset to be provided."
            return
          end

          topics.each do |topic|
            iterator = TopicIterator.new(
              topic: topic,
              group: options[:group],
              shell: shell,
              stream_processors: stream_processors,
              limit: options[:limit] || DEFAULT_LIMIT,
              min_offset: options[:min_offset],
              max_offset: options[:max_offset],
              after: options[:after],
              before: options[:before],
              payload_pattern: options[:payload],
              error_pattern: options[:error],
              noninteractive: options[:yes],
              processor_name: options[:processor],
            )
            iterator.replay_messages
          end
        end

        private

        def stream_processors
          GitHub::StreamProcessors::BaseProcessor.descendants
        end
      end
    end
  end
end
