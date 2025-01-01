# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Perform a RPC roundtrip, returning whatever's provided as input.
    # This is primarily useful in tests and network analysis.
    #
    # obj - Any serializeable type. Hashes, arrays, and scalars.
    #
    # Returns the argument provided without modification.
    def echo(obj = nil)
      # Explicitly pass empty kwargs. Otherwise, in ruby 2.7, an 'obj' that's a
      # hash with only symbol keys will be interpreted as being keyword
      # parameters.
      kwargs = {}
      send_message :echo, obj, **kwargs
    end

    def async_echo(obj = nil)
      async_send_message :echo, obj
    end

    # Public: Emulate a slow response by sleeping on the server side. This is
    # primarily useful for network analysis and testing RPC protocol support
    # for call timeouts.
    #
    # time - Float amount of time to sleep in seconds. If this value is greater
    #        than the configured RPC timeout, the call should not return and
    #        instead raise an exception.
    #
    # Returns the literal string "OK".
    #
    # Raises a `GitRPC::Timeout` when the sleep time exceeds the configured
    # timeout value.
    def slow(time)
      send_message :slow, time
    end

    def async_slow(time)
      async_send_message :slow, time
    end

    def slow_reader(time)
      send_message :slow_reader, time
    end

    def async_slow_reader(time)
      async_send_message :slow_reader, time
    end

    # Public: generate a random number on the server side.  This is a
    # simple way to make multiple, identical calls produce different
    # results.
    def rand
      send_message :rand
    end

    def async_rand
      async_send_message :rand
    end

    # Public: generate a random number on the server side.  This is
    # just like rand() except it's tagged read-only, so it will only
    # run on one backend.
    def one_rand
      send_message :one_rand
    end

    def async_one_rand
      async_send_message :one_rand
    end

    # Public: Check whether the repository is available.
    def online?
      send_message :online?
    rescue GitRPC::NetworkError, GitRPC::NoDataError
      false
    end

    def async_online?
      # match the above behaviour by converting GitRPC::NetworkError rejections into
      # fulfillment with 'false'.
      async_send_message(:online?).rescue do |reason|
        if reason.is_a?(GitRPC::NetworkError) || reason.is_a?(GitRPC::NoDataError)
          false
        else
          raise reason
        end
      end
    end
  end
end
