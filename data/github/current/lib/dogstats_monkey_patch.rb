# typed: false
# frozen_string_literal: true

# TODO: Remove this monkey patch when the fixes to dogstats is upstreamed

module Datadog
  class Statsd
    # This monkey patch causes the sender thread to poll for work rather than wait()
    # on the queue to have data ready. The wait() pattern results in a lock convoy on the GIL,
    # which causes a high rate of context-switching.
    # See Also:
    #  - https://gist.github.com/jpl-coconut/90b374bafb0a9b030c164148957fdfe1
    #  - https://github.com/github/performance-engineering/issues/1644
    #  - https://github.com/jpl-coconut/dogstatsd-ruby/tree/sleep_wait
    #
    # This code is equivalent to:
    #  - https://github.com/jpl-coconut/dogstatsd-ruby/blob/sleep_wait/lib/datadog/statsd/sender.rb

    # Sender is using a companion thread to flush and pack messages
    # in a `MessageBuffer`.
    # The communication with this thread is done using a `Queue`.
    # If the thread is dead, it is starting a new one to avoid having a blocked
    # Sender with no companion thread to communicate with (most of the time, having
    # a dead companion thread means that a fork just happened and that we are
    # running in the child process).
    if ENV["DATADOG_MONKEY_PATCH_SENDER_ENABLED"] == "1"
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

    # This is a different patch from the one above. This one moves the Socket#sendmsg_nonblock
    # syscall into a dedicated ractor. Because we invoke that syscall so often (~135 times/sec)
    # and the syscall takes so long (~150usec), having it on the main ractor causes a lot
    # of context switching. The unit tests are all in the branch of dogstatsd.
    #
    # This code is equivalent to:
    #  - https://github.com/jpl-coconut/dogstatsd-ruby/blob/ractor/lib/datadog/statsd/uds_connection.rb
    class UDSSender
      def initialize(socket_path)
        @socket_path = socket_path
        @socket = nil
      end

      def close
        @socket.close if @socket
        @socket = nil
      end

      attr_reader :socket

      def connect
        close if @socket

        @socket = Socket.new(Socket::AF_UNIX, Socket::SOCK_DGRAM)
        @socket.connect(Socket.pack_sockaddr_un(@socket_path))
      end

      # send_message is writing the message in the socket, it may create the socket if nil
      # It is not thread-safe but since it is called by either the Sender bg thread or the
      # SingleThreadSender (which is using a mutex while Flushing), only one thread must call
      # it at a time.
      def send_message(message)
        connect unless @socket
        @socket.sendmsg_nonblock(message)
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ENOENT => e
        # TODO: FIXME: This error should be considered as a retryable error in the
        # Connection class. An even better solution would be to make BadSocketError inherit
        # from a specific retryable error class in the Connection class.
        raise UDSConnection::BadSocketError, "#{e.class}: #{e}"
      end
    end

    class UDSRactorProxy
      # This is only used for testing. There is no need to support concurrent update.
      @init_count = 0

      class << self
        attr_accessor :init_count
      end

      def initialize(socket_path)
        @socket_path = socket_path
        self.class.init_count += 1
      end

      def connect
        close if @ractor_sender
        previous_exp = Warning[:experimental]
        begin
          # Without this, creating the ractor will throw an exception in ruby 3.x
          Warning[:experimental] = false
          @ractor_sender = Ractor.new(@socket_path) do |socket_path|
            # This is the only way to safely log from inside a ractor. We write to STDERR
            # directly.
            logger = IO.for_fd(2, "w")
            sender = UDSSender.new(socket_path)
            loop do
              message = Ractor.receive
              unless message
                sender.close
                break
              end

              begin
                sender.send_message(message)
              rescue StandardError => e
                # The send is intentionally asynchronous so there is no way to deliver this
                # reliably to the caller. We can log.
                logger.syswrite "Failed to send message via UDS ractor for socket #{socket_path}: #{e}\n"
              end
            end
          end
        ensure
          Warning[:experimental] = previous_exp
        end
      end

      def send_message(message)
        tries = 0
        while true
          begin
            connect unless @ractor_sender
            # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
            @ractor_sender.send(message)
            # rubocop:enable GitHub/AvoidObjectSendWithDynamicMethod
            break
          rescue Ractor::ClosedError
            # The Ractor is dead, most likely because a fork happened and we are now
            # running in the child process where the parent's Ractor thread no longer
            # exists. Recreate the Ractor and retry the send.
            @ractor_sender = nil
            tries += 1
          end
          if tries >= 2
            warn "Datadog::Statsd::UDSRactorProxy failed to send message after #{tries} attempts due to Ractor::ClosedError"
            break
          end
        end
      end

      def close
        return unless @ractor_sender
        begin
          # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
          @ractor_sender.send(nil)
          # rubocop:enable GitHub/AvoidObjectSendWithDynamicMethod
        rescue StandardError => e
          if defined?(Ractor::ClosedError) && e.is_a?(Ractor::ClosedError)
            # The ractor port may already be closed, which is fine
          else
            raise e
          end
        end
        @ractor_sender = nil
      end
    end

    class UDSConnection < Connection
      class BadSocketError < StandardError; end

      # DogStatsd unix socket path
      attr_reader :socket_path

      def initialize(socket_path, **kwargs)
        super(**kwargs)
        @socket_path = socket_path

        if ENV["DOGSTATS_USE_RACTOR"]
          @socket_sender = UDSRactorProxy.new(socket_path)
        else
          @socket_sender = UDSSender.new(socket_path)
        end
      end

      def close
        @socket_sender.close
      end

      # Helper for rspec tests to access the underlying socket when not using the
      # Ractor-based implementation.
      #
      # When DOGSTATS_USE_RACTOR is enabled this method intentionally returns nil,
      # because the Ractor proxy does not expose a direct Socket instance.
      def socket
        unless ENV["DOGSTATS_USE_RACTOR"]
          @socket_sender.socket
        end
      end

      private

      def send_message(message)
        @socket_sender.send_message(message)
      end

      def connect
        @socket_sender.connect
      end
    end
  end
end
