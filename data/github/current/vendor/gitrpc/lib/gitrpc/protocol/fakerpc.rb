# rubocop:disable Style/FrozenStringLiteralComment
require "bert"

module GitRPC
  class Protocol
    # Protocol implementation for "fakerpc:<path>" URLs. This protocol is
    # designed to emulate a remote RPC connection for local access and is
    # typically used in development environments and tests. It's a simple
    # wrapper over the 'file:' protocol that serializes call arguments and
    # response data to ensure that calls do not include objects that cannot
    # be sent over the wire.
    #
    # The <path> component must be a full absolute path to the repository's
    # disk location on the local machine.
    #
    # This class shouldn't be created directly. Instead, use:
    #
    #     GitRPC.new("fakerpc:/path/to/repo.git")
    #
    class FakeRPC < Protocol
      # The URI object used to construct this object.
      attr_reader :url

      # The full path to the repository on disk as a string.
      attr_reader :path

      # The backend behind the fakerpc
      def backend
        @backend.backend
      end

      # Create a new fake RPC access protocol for the given path.
      def initialize(url, options = {})
        fail if url.scheme != "fakerpc"
        @url  = url
        @path = url.path || url.opaque
        @backend = GitRPC::Protocol.resolve("file:#{@path}", options)
      end

      # Creates a new GitRPC::Backend object. This is called prior to each
      # RPC message to emulate over-the-wire behavior. Otherwise, the same
      # Backend object is used to process multiple messages and the
      # Rugged::Repository maintains state about refs and whatnot between
      # requests resulting in slightly different behavior in some cases.
      def reset_backend
        @backend = GitRPC::Protocol.resolve("file:#{@path}", options)
      end

      # Must expose the provided options hash.
      def options
        @backend.options
      end

      # Default repository scope cache key
      def repository_key
        @backend.repository_key
      end

      # Default repository reference key
      def repository_reference_key
        @backend.repository_reference_key
      end

      # Make an RPC call on the backend. Call arguments are checked for
      # serialization compatibility by encoding/decoding with msgpack. Call
      # results are also encoded/decoded.
      #
      # Uses GitRPC::Failure to wrap the exception if necessary using the
      # same logic as remote protocols.
      #
      # A special :emulate_error message can be sent to emulate the raising of
      # a specific exception. The first argument to the call is the exception
      # class or instance to raise in that case. This object need not be
      # serializable.
      def send_message(message, *args, **kwargs)
        if message.to_sym == :emulate_error
          raise args[0]
        end

        begin
          message, args = verify_encoding([message, args, kwargs])

          start = Time.now
          reset_backend
          begin
            res = @backend.send_message(message, *args, **kwargs)
          ensure
            if GitRPC.test_tracer
              GitRPC.test_tracer.record_send_message(path: @path, message:, start:, err: $!)
            end
          end

          verify_encoding(res)
        rescue => boom
          GitRPC::Failure.raise(boom)
        end
      end

      def async_send_message(message, *args, **kwargs)
        Promise.resolve.then do
          send_message(message, *args, **kwargs)
        end
      end

      # Encode and then decode the object given using the wire serialization.
      # This creates a deep copy of the object, emulating the behavior of
      # going over the wire. This can help surface behavior that depends on
      # object modifications on the remote side effecting the client side.
      #
      # object - Any BERT compatible object.
      #
      # Returns the decoded version of the given object.
      # Raises a GitRPC::EncodingError if an exception occurs while encoding or
      # decoding.
      def verify_encoding(object)
        data = BERT.encode(object)
        BERT.decode(data)
      rescue => boom
        raise GitRPC::EncodingError, boom
      end
    end
  end
end
