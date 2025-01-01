# typed: false
# frozen_string_literal: true

# ThrottledLogger wraps a Logger instance to reduce duplicate log messages
# during an interval of time to reduce log volume during noisy error conditions.
module GitHub
  class ThrottledLogger

    # The maximum number of log messages we'll track at any time. Failsafe for
    # extremly noisy logging scenarios to prevent unbounded memory growth.
    MAX_SEEN = 1000

    # Initialize a throttled logger
    #
    # logger - the logger to wrap
    # delay  - how long to wait in seconds before allowing a repeated message
    def initialize(logger, delay: 10)
      @delay = delay
      @logger = logger

      @lock = Mutex.new
      @seen = Hash.new
    end

    def debug(message = nil, &block)
      add(::Logger::DEBUG, message, nil, &block)
    end

    def info(message = nil, &block)
      add(::Logger::INFO, message, nil, &block)
    end

    def warn(message = nil, &block)
      add(::Logger::WARN, message, nil, &block)
    end

    def error(message = nil, &block)
      add(::Logger::ERROR, message, nil, &block)
    end

    def fatal(message = nil, &block)
      add(::Logger::FATAL, message, nil, &block)
    end

    def add(severity, message = nil, progname = nil, &block)
      @lock.synchronize do
        # scan for expired entries
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        expire = now - @delay
        @seen.delete_if { |_k, v| v < expire }

        # run the block here so we can deduplicate the resulting message
        if message.nil? && block_given?
          message = yield
        end

        # log this message, but prevent its duplicate
        key = [severity, message, progname]
        unless @seen[key]
          @seen[key] = now
          @logger.add severity, message, progname
        end

        # Trim if we're trying to track too much
        if @seen.length > MAX_SEEN
          @seen.keys.first(@seen.length - MAX_SEEN).each do |key|
            @seen.delete key
          end
        end

      end

      true # match Logger#add return value
    end

    # delegate everything else
    def method_missing(meth, *args, **kwargs)
      @logger.send(meth, *args, **kwargs)
    end

  end

end
