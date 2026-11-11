# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module DeadLetter
      class TopicIterator
        extend Forwardable
        def_delegators :shell, :ask, :indent, :print_wrapped, :say, :set_color, :yes?

        attr_reader :topic, :group, :shell, :stream_processors, :limit, :min_offset, :max_offset, :min_timestamp, :max_timestamp, :payload_pattern, :error_pattern, :noninteractive, :processor_name

        alias_method :noninteractive?, :noninteractive

        def initialize(topic:, group:, shell:, stream_processors:, limit:, min_offset: nil, max_offset: nil, before: nil, after: nil, payload_pattern: nil, error_pattern: nil, noninteractive: false, processor_name: nil)
          @topic = topic
          @group = group
          @shell = shell
          @stream_processors = stream_processors.map(&:new)

          @limit = limit
          @min_offset = min_offset
          @max_offset = max_offset
          @min_timestamp = Time.parse(after) if after
          @max_timestamp = Time.parse(before) if before
          @payload_pattern = Regexp.new(payload_pattern, Regexp::IGNORECASE) if payload_pattern
          @error_pattern = Regexp.new(error_pattern, Regexp::IGNORECASE) if error_pattern

          @noninteractive = !!noninteractive
          @processor_name = processor_name
        end

        def replay_messages
          return unless current_replay_processor = replay_processor

          current_replay_processor_name = current_replay_processor.class.name.sub(/\AGitHub::StreamProcessors::/, "")

          print_messages do |message|
            if noninteractive? || yes?("Replay this message using #{set_color(current_replay_processor_name, :green)}? (y/n)")
              current_replay_processor.execution_context["replay"] = true
              if current_replay_processor.batching?
                current_replay_processor.process_with_consumer([message], consumer)
              else
                current_replay_processor.process_with_consumer(message, consumer)
              end
            end
          end
        end

        def show_messages
          print_messages
        end

        private

        def replay_processor
          say
          case
          when processor_name.present?
            replay_processor = stream_processors.detect { |p| p.class.name == processor_name }

            unless replay_processor
              say "#{set_color('ERROR:', :red, :bold)} Unknown Hydro processor '#{processor_name}'. "
              say "You must specify a fully-qualified class name with the --processor option."
              return
            end
          when replay_processors.many?
            say "Multiple Hydro processors publish to the topic #{topic}:"
            say

            indent do
              replay_processors.each { |p| say p.class.name }
            end
            say

            replay_processor = T.let(nil, T.nilable(BaseProcessor))
            until replay_processor
              answer = ask("Enter Hydro processor name to use:")
              replay_processor = replay_processors.detect { |p| p.class.name == answer }
              say "#{set_color('ERROR:', :red, :bold)} Unknown Hydro processor #{answer}." unless replay_processor
            end
          when replay_processors.none?
            say "#{set_color('ERROR:', :red, :bold)} No Hydro processor publishes messages to #{topic}. "
            say "Use --processor to manually specify the Hydro processor to use. You must specify a "
            say "fully-qualified class name."
            return
          else
            replay_processor = replay_processors.first
          end
          replay_processor
        end

        def print_messages
          consumer.open

          say "Looking for messages on topics matching ", :bold
          say topic, :green

          messages_fetched = 0
          last_batch_received_at = Time.current

          Thread.new do # rubocop:disable GitHub/ThreadUse
            loop do
              if last_batch_received_at < 10.seconds.ago
                say "No new messages received for 10 seconds - we're probably at the front of the queue. Stopping."
                consumer.close
                break
              else
                sleep 1
              end
            end
          end

          begin
            consumer.each_batch do |batch|
              last_batch_received_at = Time.current
              say "Fetched #{batch.length} messages"

              batch.each do |message|
                next if min_offset && message.offset < min_offset
                break if max_offset && message.offset > max_offset

                message_timestamp = Time.at(message.timestamp)
                next if min_timestamp && message_timestamp < min_timestamp
                break if max_timestamp && message_timestamp > max_timestamp

                next if payload_pattern && !payload_pattern.match?(message.value[:payload])
                next if error_pattern && !(error_pattern.match(message.value[:error_class]) || error_pattern.match(message.value[:error_message]))

                say "---", :cyan
                say "Topic: ", :bold
                say "#{message.topic}  ", :green
                say "Partition: ", :bold
                say "#{message.partition || 'n/a'}  ", :green
                say "Offset: ", :bold
                say "#{message.offset}  ", :green
                say "Timestamp: ", :bold
                say message_timestamp, :green

                say "Payload:", :bold
                say message.value[:payload]

                say "Error: ", :bold
                say "#{message.value[:error_class]} ", :yellow
                say "- #{message.value[:error_message]}"

                yield message if block_given?
                consumer.mark_message_as_processed(message)

                messages_fetched += 1
                break if messages_fetched >= limit
              end
            end
          rescue Hydro::Source::Error => e
            say
            say "An error occurred while fetching messages from Hydro: #{e.message}"
            say "This is probably fine! But if you re-run this command with --group '#{group}', you may see some of the same messages again. Use caution to avoid re-processing the same dead letter messages multiple times."
          end

          consumer.close

          if messages_fetched >= limit
            say
            print_wrapped "Showing #{messages_fetched} messages from topics matching #{topic}. Use --limit to show more or fewer messages. Use --group '#{group}' to continue processing from this point."
          end
        end

        def consumer
          @consumer ||= GitHub.hydro_consumer(
            group_id: group,
            subscribe_to: /#{Regexp.escape(topic)}\z/,
            automatically_mark_as_processed: false,
          )
        end

        def replay_processors
          @replay_processors ||= stream_processors.select do |stream_processor|
            next false if stream_processor.dead_letter_topic.nil?
            /#{Regexp.escape(stream_processor.dead_letter_topic)}\z/ =~ topic
          end
        end
      end
    end
  end
end
