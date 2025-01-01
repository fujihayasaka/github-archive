# rubocop:disable Style/FrozenStringLiteralComment
require "gitrpc/util"
require "digest/sha2"

module GitRPC
  # GitRPC::Client contains network frontend logic for all GitRPC commands. This
  # part of the library is always available regardless of whether the GitRPC::Backend
  # is being accessed remotely and is the main RPC interface for client code.
  #
  # All public GitRPC::Backend methods are available on the Client interface.
  # Many have special client-side fronting methods that perform the following
  # types of logic:
  #
  # - Caching. Batch operations on content addressable objects like commits,
  #   trees, and blobs rarely need to go to the backend since these objects are
  #   likely to be hot in cache. The client methods first load these objects
  #   from memcache, then make a call on the backend for any objects that cache
  #   miss. This is a major aspect of why these method implementations exist.
  #
  # - Fast path and short circuiting logic. For instance, the #rev_parse command
  #   avoids a network round trip when a valid full sha1 is provided since we know
  #   the exact same behavior will occur remotely.
  #
  # Remote Access
  # -------------
  #
  # Client method implementations and calling code should never assume local
  # machine access to repositories on disk. The provided backend object must be
  # used for all git access.
  #
  # Cache Keys
  # ----------
  #
  # The Client interface includes a number of methods for generating the cache
  # keys used to store git objects and other data. The content_cache_key,
  # repository_cache_key, and repository_reference_cache_key helper methods
  # should be used to generate these keys.
  #
  # The content_key and repository_key attributes as well as repository_reference_key_delegate
  # should be set to the best possible values.
  class Client
    include Scientist

    # The GitRPC::Backend compatible object to make calls on. This object is
    # consulted on cache miss as well as any command that has no client
    # implementation.
    #
    # Note that the backend object may have some remoting goo strapped over top
    # of it. It must respond to all backend methods, though.
    attr_reader :backend

    # The memcache client. A Dalli object or something that supports
    # Dalli's basic interface. This object must respond to the #get, #set,
    # #get_multi, and #delete methods.
    #
    # https://github.com/mperham/dalli
    attr_reader :cache

    # The memcache client used for deferred cache writes which have a reduced
    # QOS which is strictly best-effort. This is a GitHub::LazyMemcache object
    # or something that supports its interface. This object must respond to the
    # #set method and does not currently support encoding of any kind, so can
    # only handle strings.
    attr_reader :lazy_cache

    # A boolean value representing the default value to be used for feature
    # flags if a 'feature_enabled' function has not been defined for this
    # client. This value should always be 'false' except when running GitRPC
    # tests with the TEST_ALL_FEATURES environment variable set to "1".
    class << self
      attr_accessor :feature_default
    end
    @feature_default = false

    # Outside of tests, this function is essentially a no-op, always returning
    # 'false' and allowing Scientist experiments to run as usual.
    #
    # In some tests, we check the number of calls made to GitRPC. In these cases,
    # the double-calls of the experiments may trigger failure. This function
    # should be mocked to return 'true' for those tests.
    def self.disable_experiments?; false; end

    # Create a new GitRPC::Client with the given Backend and Caches.
    #
    # backend    - The GitRPC::Backend compatible object with access to the
    #              underlying git repository.
    # cache      - A memcache client object. Must support Dalli's basic interface.
    # lazy_cache - A deferred memcache client object. Must support the interface
    #              of GitHub::LazyMemcache.
    #
    # The content_key, repository_key, network_key attributes should be set to
    # sensible values after the client is created. The caller should also use
    # repository_reference_key_delegate, when appropriate, to help with cache
    # invalidation for the refs cache.
    def initialize(backend, cache, lazy_cache)
      @backend = backend
      @app = GitRPC::Middleware.new(backend) do
        use GitRPC::Middleware::Instrumentation
        use GitRPC::Middleware::EnsureValidCall
      end

      @content_key = ""
      @repository_key = nil
      @network_key = nil

      self.cache = cache
      self.lazy_cache = lazy_cache
    end

    # Check whether a feature flag is enabled. Uses the 'feature_enabled'
    # function, if set, to check the feature flag value with Flipper. Otherwise,
    # falls back on the default (typically false; see 'feature_default' above).
    #
    # feature_name - Symbol identifying the feature flag to look up.
    #
    # Returns boolean flag value.
    def feature_enabled?(feature_name)
      @feature_enabled ? @feature_enabled.call(feature_name) : GitRPC::Client.feature_default
    end
    attr_writer :feature_enabled

    # Public: Backend execution options. These values may be modified after
    # creation. Modifications effect subsequent calls. See the GitRPC module
    # documentation for available options.
    #
    # Returns the options hash passed to backend command invocations.
    def options
      @backend ? @backend.options : {}
    end

    # Run a block with the GitRPC timeout temporarily set to the
    # specified value rather than the default (which at the time of this
    # writing is 9 seconds for production and 30 minutes for resque
    # jobs). timeout should be either an integer or float number of
    # seconds, or a Duration like `5.minutes`.
    def with_timeout(timeout)
      original_timeout = options[:timeout]
      options[:timeout] = timeout.to_f
      yield
    ensure
      options[:timeout] = original_timeout
    end

    # Public: Make an RPC call on the backend. This is provided as a chokepoint
    # for logging and instrumentation. If the backend is remote, the message is
    # encoded and sent over the wire.
    #
    # This method is used primarily by the client method implementations. It
    # should be used sparingly (if at all) by calling code.
    #
    # message - The name of the method to invoke on the backend as a symbol.
    # args    - Zero or more arguments to pass to the method. This must consist
    #           of only primitive types and hashes should use string keys.
    #
    # Returns whatever's returned from the backend. This must consist of only
    # primitive types: arrays, hashes with string keys, and scalars.
    def send_message(message, *args, **kwargs)
      @app.send_message(message, *args, **kwargs)
    end

    def async_send_message(message, *args, **kwargs)
      @app.async_send_message(message, *args, **kwargs)
    end

    # Public: Make an RPC call on a replicated backend, and return a hash
    # of {route => response}.  This is similar to send_message, but it
    # tolerates replicas that produce different responses.  It only makes
    # sense for remote backends; the message is encoded and sent over the
    # wire.
    #
    # Only call this if the backend implements send_demux and returns true
    # for disagreement_possible?.
    #
    # This method is used primarily by the client method implementations. It
    # should be used sparingly (if at all) by calling code.
    #
    # message - The name of the method to invoke on the backend as a symbol.
    # args    - Zero or more arguments to pass to the method. This must consist
    #           of only primitive types and hashes should use string keys.
    #
    # Returns a hash mapping { route => response }, for the route to each
    # replica and the response provided by the backend at each replica.
    def send_demux(message, *args, **kwargs)
      @app.send_demux(message, *args, **kwargs)
    end

    # All common internal utility functions are available to client call
    # implementations.
    include GitRPC::Util

    # Client method implementations are split up into separate files for
    # organization purposes. The test file structure mirrors this.
    Dir[File.expand_path("../client/*.rb", __FILE__)].each do |file|
      name = File.basename(file, ".rb")
      require "gitrpc/client/#{name}"
    end

    # Set the cache connection
    def cache=(conn)
      @cache = conn
    end

    # Set the lazy_cache connection
    def lazy_cache=(conn)
      @lazy_cache = conn
    end

    # Public: Cache prefix used for all "content addressable" items. This
    # includes all git objects like commits, trees, blobs, and tags. Leaving
    # this value nil or using a value that's shared between multiple
    # repositories results in the cache space being shared.
    #
    # This key is blank by default. It's typically set to prevent cache space
    # from being shared in the case of, e.g., GitHub's private repos. It's an
    # extra safeguard against possible infoleak.
    attr_accessor :content_key

    # Public: Used to generate cache keys for "repository scope" objects. This
    # is used primarily for refs. Non content addressable items only.
    #
    # The value should uniquely identify the repository amongst all other
    # repositories in the cache space. This should be a primary key field from
    # a database but can be anything really.
    def repository_key
      @repository_key || @backend.repository_key
    end
    attr_writer :repository_key

    # Public: Used to generate cache keys for "netowrk scope" objects.
    #
    # The value should uniquely identify the network amongst all other
    # netowkrs in the cache space. This should be a primary key field from
    # a database but can be anything really.
    def network_key
      @network_key || @backend.network_key
    end
    attr_writer :network_key

    # Public: invalidate and force the repository reference cache key to be
    # recomputed. This is typically performed after any ref updates.
    def clear_repository_reference_key!
      @repository_reference_key = nil
    end

    # Public: Set the repository's reference cache key manually with a checksum.
    # This should not need to be called usually, but it is used after reference
    # updates in order to set the new reference key when we are inside a transaction.
    def set_repository_reference_key!(key)
      @repository_reference_key = key
    end

    # Public: The repository's reference cache key. If none is set, returns the
    # current timestamp in milliseconds since the UNIX epoch.
    def repository_reference_key
      @repository_reference_key ||= repository_reference_key_delegate.repository_reference_key || default_repository_reference_key
    end

    # Public: The object that knows how to calculate the repository_reference_key.
    #
    # GitRPC will ask the @backend for a ref key first, so that the DGit apparatus
    # can provide a value.
    attr_writer :repository_reference_key_delegate
    def repository_reference_key_delegate
      @repository_reference_key_delegate || @backend
    end

    # Private: If no ref key is defined, use this instead.
    def default_repository_reference_key
      "now/#{"%d" % (Time.now.to_f * 1000.0)}"
    end

    # Internal: Generate a cache key for an immutable and content addressable
    # piece of content like a commit, tree, or blob. This uses the content_key
    # attribute as a base prefix. See the attribute docs for more info on
    # content addressable cache keys.
    #
    # parts - Array of additional stuff to include in the key. This must consist
    #         of valid memcache key characters only. Use the sha256 digest for path
    #         names and other elements that may include weird characters.
    #
    # Returns a string key suitable for use with memcache.
    def content_cache_key(*parts)
      [cache_version, content_key, *parts].join(":")
    end

    # Internal: Generate a cache key for repository scoped data. Anything cached
    # under this key is guaranteed to not be shared with other repositories.
    #
    # parts - Array of additional cache key elements.
    #
    # Returns a string key suitable for use with memcache.
    def repository_cache_key(*parts)
      [cache_version, repository_key, *parts].join(":")
    end

    # Internal: Generate a cache key for network scoped data. Anything cached
    # under this key is guaranteed to not be shared with other repositories.
    #
    # parts - Array of additional cache key elements.
    #
    # Returns a string key suitable for use with memcache.
    def network_cache_key(*parts)
      [cache_version, network_key, *parts].join(":")
    end

    # Internal: Generate a cache key for the repository's references. This key
    # changes whenever the repository's ref state changes.
    #
    # parts - Array of additional cache key elements.
    #
    # Returns a string key suitable for use with memcache.
    def repository_reference_cache_key(*parts)
      [cache_version, repository_key, repository_reference_key, *parts].join(":")
    end

    def cache_version
      "v2"
    end

    # Internal: Generate an sha256 sum of the passed strings. Used to
    # generate fixed length representation of variable length parameters
    # to be used as cache keys
    #
    # parts - Array of variable length keys to sha256sum
    #
    # Returns a sha256 hash string of the parameters
    def sha256(*parts)
      Digest::SHA256.hexdigest(parts.join(":"))
    end
  end
end
