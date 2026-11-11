# rubocop:disable Style/FrozenStringLiteralComment
module GitRPC
  class Protocol
    # Protocol implementation for "file:<path>" URLs. The <path> must be a full
    # absolute path to the repository's disk location on the local machine.
    #
    # This class shouldn't be created directly. Instead, use:
    #
    #     GitRPC.new("file:/path/to/repo.git")
    #
    # This protocol implementation is fairly simple since no remote access is
    # needed to access the repository. This is one of the few cases where
    # GitRPC::Backend runs in the same process as the Protocol implementation.
    # The implementation delegates directly to Backend for most methods.
    class File < Protocol
      # The URI object used to construct this object.
      attr_reader :url

      # The full path to the repository on disk as a string.
      attr_reader :path

      # The GitRPC backend object
      attr_reader :backend

      # Create a new local machine access protocol for the given path.
      def initialize(url, options = {})
        fail if url.scheme != "file"
        @url  = url
        @path = url.path || url.opaque
        @backend = GitRPC::Backend.new(@path, options)
      end

      # Make an RPC call on the backend. Uses GitRPC::Failure to wrap the
      # exception if necessary using the same logic as remote protocols.
      def send_message(message, *args, **kwargs)
        backend.send_message(message, *args, **kwargs)
      rescue => boom
        GitRPC::Failure.raise(boom)
      ensure
        backend.cleanup if backend
      end

      def async_send_message(message, *args, **kwargs)
        Promise.resolve.then do
          send_message(message, *args, **kwargs)
        end
      end

      # Must expose the provided options hash.
      def options
        backend.options
      end

      # Default repository scope cache key
      def repository_key
        backend.repository_key
      end
    end
  end
end
