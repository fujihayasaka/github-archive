# frozen_string_literal: true

require "uri"
require "gitrpc/error"

require "gitrpc/protocol/bertrpc"
require "gitrpc/protocol/chimney_transitional"
require "gitrpc/protocol/dgit"
require "gitrpc/protocol/fakerpc"
require "gitrpc/protocol/file"

module GitRPC
  # GitRPC::Protocol is the base class for all "remote" git access. Actually
  # that's not true, local git access requires a Protocol implementation as well
  # but the basic idea is to abstract and mediate communication between the
  # client side GitRPC::Client and the possibly remotely hosted GitRPC::Backend.
  #
  # Each protocol subclass is responsible for dealing with the following
  # concerns for its specific protocol:
  #
  # - URL resolution. The ::resolve class method takes a URI and must return a
  #   Protocol instance. The URL may include a variety of information based on
  #   the type of access protocol. See the protocol implementations for more
  #   details.
  #
  # - Network access. This typically involves encoding send_message calls using
  #   whatever RPC or message encoding, sending them over the wire, and decoding
  #   the result. For local machine protocols like "file", there may not be
  #   anything to do here.
  #
  # - Error handling. GitRPC defines a number of standard error modes. Protocol
  #   subclasses are responsible for translating protocol-specific errors to
  #   these standard error descriptions. This allows calling code to be written
  #   portably across network protocols and access methods.
  #
  # The Protocol base class provides very little actual functionality. It mostly
  # exists to define and document the expected Protocol interface. The mapping
  # of protocol schemes to implementation classes is maintained here.
  class Protocol

    # Public: Create a new Protocol instance for the given URL. Protocol
    # implementations must support this creation interface exactly.
    #
    # url     - A URI object resulting from calling URI.parse(string). The
    #           #host, #port, #path, and #query attributes are used by most
    #           Protocol types. The #opaque attribute can also be useful for
    #           non-standard URL types like the Chimney protocol.
    # options - Hash of options to pass to the Backend. The :timeout and :max
    #           options may be interperted by the Protocol implementation
    #           itself.
    #
    # Returns a Protocol instance. The object must handle all of the
    # responsibilities documented here and implement all public methods.
    def initialize(url, options = {})
      raise NotImplementedError
    end

    # Public: The URI object provided when the object was constructed. All
    # Protocol implementations must expose this.
    def url
      raise NotImplementedError
    end

    # Public: All protocol subclasses must respond to #options with the options
    # hash provided to its initializer.
    def options
      raise NotImplementedError
    end

    # Public: Send a message to the backend. All calls not handled entirely by
    # GitRPC::Client eventually move through this choke point. Subclasses are
    # responsible for performing any network access and translating error
    # modes.
    #
    # message - The name of the method to invoke on the backend as a symbol.
    # args    - Zero or more arguments to pass to the method. This must consist
    #           of only primitive types and hashes should use string keys.
    # kwargs  - Keyword arguments to pass to the method.
    #
    # Returns whatever's returned from the backend. This must consist of only
    # primitive types: arrays, hashes with string keys, and scalars.
    #
    # Raises any of the core GitRPC::Error types or a GitRPC::Failure when an
    # unhandled exception occurred in a handler. Subclasses are responsible for
    # mapping protocol errors onto the standard GitRPC errors and performing
    # basic exception handling with GitRPC::Failure.
    def send_message(message, *args, **kwargs)
      raise NotImplementedError
    end

    def async_send_message(message, *args, **kwargs)
      raise NotImplementedError
    end

    # Internal: Call a method on the protocol. Allows for sending a message down
    # through the middleware stack and have it called properly on the protocol
    #
    # meth - The method to call
    # *args - The args to send to the method
    def call(meth, *args, **kwargs)
      __send__(meth, *args, **kwargs)
    end

    # Public: String key that uniquely identifies the repository. Used by
    # GitRPC::Client when no repository key is explicitly configured by the
    # caller. Protocol implementations should return the best key possible
    # given the information provided in the URL.
    #
    # Returns a string key suitable for use with memcache. Keys that may
    # include invalid characters should be run through SHA256.hexdigest.
    def repository_key
      raise NotImplementedError
    end

    # Public: By default, this doesn't know anything about how to calculate
    # the repository reference key. GitRPC::Client provides a fallback value,
    # and subclasses can override this if they know what should be used.
    def repository_reference_key
      nil
    end

    # Public: Returns true if the protocol communicates with multiple
    # backends and those backends might disagree, leading to a
    # Disagreement error.  Any protocol that returns true here must also
    # implement `send_demux` to retrieve all backends' answers separately
    # instead of raising an error if they disagree.
    def disagreement_possible?
      false
    end

    # Protocol Registry
    # -----------------
    # The following class methods are for maintaining the global protocol
    # scheme mappings.

    # Hash of protocol scheme to protocol class name mappings. This is used to
    # lookup and load the Protocol subclass needed for a given URL scheme. Hash
    # keys are the URL "scheme" or protocol part. Values may be a Protocol
    # subclass or a string referencing a protocol subclass to delay loading
    # until first use.
    def self.registry
      @registry ||= {
        "file"                 => GitRPC::Protocol::File,
        "bertrpc"              => GitRPC::Protocol::BERTRPC,
        "fakerpc"              => GitRPC::Protocol::FakeRPC,
        "chimney-transitional" => GitRPC::Protocol::ChimneyTransitional,
        "dgit"                 => GitRPC::Protocol::DGit,
      }.freeze
    end

    # Register or replace a protocol
    def self.register(name, klass)
      @registry = registry.merge(name => klass).freeze
    end

    # Look up a URL in the registry based on its scheme and return a new
    # instance of the Protocol class.
    #
    # url     - String URL or URI object to lookup.
    # options - GitRPC options hash made available to the backend.
    #
    # Returns an instance of a Protocol subclass.
    # Raises a GitRPC::NoSuchProtocol error when no Protocol implementation
    # exists for the url.scheme specified.
    def self.resolve(url, options = {})
      url = URI.parse(url) if url.is_a?(String)
      if url.scheme == "local"
        nil
      elsif class_object = registry[url.scheme]
        class_object.new(url, options)
      else
        raise GitRPC::NoSuchProtocol, url.scheme
      end
    end
  end
end
