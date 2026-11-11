# typed: false
# frozen_string_literal: true

# This monkey patch replaces causes the sender thread to poll for work rather than wait()
# on the queue to have data ready. The wait() pattern results in a lock convoy on the GIL,
# which causes a high rate of context-switching.
# See Also:
#  - https://gist.github.com/jpl-coconut/90b374bafb0a9b030c164148957fdfe1
#  - https://github.com/github/performance-engineering/issues/1644
#  - https://github.com/jpl-coconut/dogstatsd-ruby/tree/sleep_wait
#
# TODO: Remove this monkey patch when the fix to dogstats is upstreamed

if ENV["DATADOG_MONKEY_PATCH_SENDER_ENABLED"] == "1"

  # This patches the Sender at
  #  https://github.com/jpl-coconut/dogstatsd-ruby/blob/sleep_wait/lib/datadog/statsd/sender.rb
  module Datadog
    class Statsd
      # Sender is using a companion thread to flush and pack messages
      # in a `MessageBuffer`.
      # The communication with this thread is done using a `Queue`.
      # If the thread is dead, it is starting a new one to avoid having a blocked
      # Sender with no companion thread to communicate with (most of the time, having
      # a dead companion thread means that a fork just happened and that we are
      # running in the child process).
      class Sender
        STATSD_SLEEP_INTERVAL = ENV.fetch("DATADOG_STATSD_SLEEP", 0.25).to_f

        if CLOSEABLE_QUEUES
          def send_loop
            loop do
              sleep STATSD_SLEEP_INTERVAL while message_queue.empty? && !message_queue.closed?

              if (message = message_queue.pop).nil? && message_queue.closed?
                break
              end

              # skip if message is nil, e.g. when message_queue
              # is empty and closed
              next unless message

              case message
              when :flush
                message_buffer.flush
              when @queue_class
                message.push(:go_on)
              else
                message_buffer.add(message)
              end
            end

            @message_queue = nil
            @sender_thread = nil
          end
        else
          def send_loop
            loop do
              sleep STATSD_SLEEP_INTERVAL while message_queue.empty?
              message = message_queue.pop

              next unless message

              case message
              when :close
                break
              when :flush
                message_buffer.flush
              when @queue_class
                message.push(:go_on)
              else
                message_buffer.add(message)
              end
            end

            @message_queue = nil
            @sender_thread = nil
          end
        end
      end
    end
  end
end
