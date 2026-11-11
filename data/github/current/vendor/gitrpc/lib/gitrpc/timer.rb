# frozen_string_literal: true

require "timeout"

# Internal timeout library. This shouldn't be used by things outside of GitRPC
# and the exceptions defined here should not be raised out of GitRPC. The
# GitRPC::Timeout error defined in gitrpc/errors.rb is the outward exception for
# timeouts.
module GitRPC
  module Timer
    TimeoutBackend = ::Timeout

    # Exception class raised when a timeout occurs. This can be overridden by
    # passing a specific exception class to #timeout.
    class Error < ::Timeout::Error
    end

    # Run a block with a timeout.
    #
    # seconds   - Number of seconds the block can run before being interrupted.
    # exception - Exception class to raise when a timeout occurs.
    #
    # Raises exception when a timeout occurs.
    def timeout(seconds, exception = GitRPC::Timer::Error, &block)
      if seconds.nil? || seconds <= 0.0
        yield
      else
        TimeoutBackend.timeout(seconds, exception, &block)
      end
    end

    # Fudge a timeout value up by a given number of seconds or by a
    # preset fudge value.
    #
    # timeout - The configured timeout. May be nil or 0.0 to mean no timeout.
    # amount  - Number of seconds (float) to increment the timeout. This is
    #           usually a small millisecond value like 0.013 = 13ms.
    #
    # The amount value may also be the symbol :client or :spawn to use the fudge
    # values set on client_timeout_fudge or spawn_timeout_fudge.
    #
    # Returns the new timeout value after fudging.
    # Returns nil when timeout is nil or 0.0.
    def fudge(timeout, amount)
      if timeout && timeout > 0
        amount = send("#{amount}_timeout_fudge") if amount.is_a?(Symbol)
        timeout + amount
      end
    end

    # Client socket timeout fudge. When a timeout is set, it's fudged up by this
    # amount at the client level. This gives deeper components enough time to
    # timeout and return, giving a deeper backtrace.
    #
    # Set this to the worst case amount of time the network will add to the call
    # and enough time for a backtrace and exception to be generated and raised
    # up the stack. Due to limitations in timeout granularity, values under
    # 300ms are unreliable. This is pretty high but should be okay.
    #
    # Returns a float number of seconds to add to client timeout values.
    def client_timeout_fudge
      @client_timeout_fudge || 0.300 # 300ms
    end
    attr_writer :client_timeout_fudge

    # Amount of time to give the spawn command to timeout, send git
    # TERM, have it clean up and collect the child.
    #
    # Returns a float number of seconds to add to spawn timeout values.
    def spawn_timeout_fudge
      @spawn_timeout_fudge || 0.100 # 100ms
    end

    extend self
  end
end
