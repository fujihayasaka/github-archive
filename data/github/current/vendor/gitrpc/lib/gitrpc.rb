# rubocop:disable Style/FrozenStringLiteralComment
# GitRPC is a network-oriented library for accessing remote git repositories
# efficiently.
#
# Options
# -------
#
# GitRPC.new takes an options hash that can be used to control the default
# environment. No options are required.
#
# :cache => connection (Dalli::Client)
# The memcache connection used to store and retrieve git objects. A global
# default may also be set using GitRPC.cache=.
#
# :env => A hash of environment variables (string)
# The environ hash is enabled for native command invocations only.
#
# :max => maximum amount of output to generate in bytes (int)
# Native commands that generate more than this amount of output are halted and
# a GitRPC::MaximumOutputExceeded is raised. By default, there is no limit on
# output size.
#
# :timeout => seconds (int)
# Native command operations are halted after this time limit and a
# GitRPC::Timeout exception is raised. By default, there is no timeout.
#
# :connect_timeout => seconds (int)
# Connection attempts from client to backend are halted after this time
# limit and a GitRPC::ConnectionError exception is raised. By default, there
# is no timeout.
#
# :alternates => [path, ...] (array)
# List of alternative object directories. This is sets the
# GIT_ALTERNATE_OBJECT_DIRECTORIES environment variable for native command
# invocations and also configures Rugged with alternate object directories.
# The value must be an array of path strings. These can be absolute paths or
# paths relative to the git repository directory. For instance, setting this
# value to ["../repo-2.git/objects"] will expand the path relative to
# repo-1.git.
#
# Usage
# -----
#
# Get this party started:
#
#     >> require "gitrpc"
#     >> git = GitRPC.new('/path/to/repository.git')
#     #<GitRPC::Client:0x10c... @backend=...>
#
# Retrieve all refs for the repository in a single hash (cached: 1 netop)
#
#     >> git.refs
#     { 'refs/heads/master' => 'deadbeee...', 'refs/head/some-branch' => ... }
#
# Read commit meta-data in batch and nothing else (cached: 1 netop)
#
#     >> git.read_commits(['deadbeee...', 'badfffff...'])
#     [{"type"=>"commit",
#       "oid"=>"d3224d5...",
#       "parents"=>["fd1545cc..."],
#       "tree"=>"6d1470d...",
#       "author"=>["Ryan Tomayko", "ryan@github.com", "2012-06-13T03:29:30Z"],
#       "committer"=>["Ryan Tomayko", "ryan@github.com", "2012-06-13T03:29:30Z"],
#       "message"=>":encoding docs",
#       "encoding"=>"UTF-8"},
#      {"type"=>"commit",
#       "oid"=>"abcdef0...",
#       ...}
#
# Read commits for all refs (cached: 2 netop)
#
#     >> git.read_commits(git.refs.values)
#     [{"type"=>"commit",...]
#
require "time"
require "gitrpc/hash_algorithm"
require "gitrpc/util"
require "gitrpc/util/bert_ext"
require "gitrpc/error"
require "gitrpc/failure"

require "gitrpc/backend"
require "gitrpc/client"
require "gitrpc/diff"
require "gitrpc/encoding"
require "gitrpc/gitmon_client"
require "gitrpc/middleware"
require "gitrpc/protocol"
require "gitrpc/send_multiple"
require "gitrpc/timer"

require "gitrpc/twirp"
require_relative "../proto/spokes.backend_twirp"

module GitRPC
  NULL_OID  = "0" * 40
  NULL_MODE = "0" * 6
  EMPTY_TREE_OID = "4b825dc642cb6eb9a060e54bf8d69288fbee4904".freeze
  NULL_CHAR = "\x00"

  # Create a new GitRPC::Client object for the given git repository URL.
  #
  # url     - String or URI identifying the git repository's location.
  # options - General options. These are passed all the way down to the backend.
  #           See the OPTIONS section above for available options. Options
  #           should have symbol keys.
  #
  # Returns a GitRPC::Client object in all its glory.
  def self.new(url, options = {})
    cache = options.delete(:cache) || self.cache
    lazy_cache = options.delete(:lazy_cache) || self.lazy_cache
    backend = GitRPC::Protocol.resolve(url, options)
    GitRPC::Client.new(backend, cache, lazy_cache)
  end

  # Make a one-off RPC call to multiple endpoints at the same time.
  #
  # urls          - any set of URLs. BERTRPC URLs will be accessed
  #                 in parallel, all others will be accessed serially.
  # message, args, kwargs
  #               - The call to send to the remote.
  # options       - General options. These are passed to all the
  #                 backends. See the OPTIONS section above.
  #
  # Returns two hashes, one with answers and one with errors,
  # keyed by URL.
  def self.send_multiple(urls, message, args, kwargs, options = {})
    GitRPC::SendMultiple.send_multiple(urls, message, args, kwargs, options)
  end

  # Set the memcache connection used by new client connections for storing and
  # retrieving cached repository data. This is typically configured by the calling
  # environment during boot. When no cache is configured, a simple hash-backed
  # cache is used.
  #
  # conn - A Dalli::Client or compatible object. The object must respond to the
  #        #get, #set, #get_multi, and #delete methods and must support raw
  #        value storage.
  #
  # It's highly recommended that a configured memcache connection be available
  # in production environments.
  def self.cache=(conn)
    @cache = conn
  end

  # Set the LazyMemcache client used for new client connections to execute
  # deferred cache writes with a best-effort QOS.  This is a
  # GitHub::LazyMemcache object or something that supports its interface.
  def self.lazy_cache=(conn)
    @lazy_cache = conn
  end

  # The Cache object used to store and retrieve values in memcache.
  def self.cache
    @cache ||= GitRPC::Util::HashCache.new
  end

  # The LazyCache object used to store deferred cache writes with a best effort QOS.
  def self.lazy_cache
    @lazy_cache ||= GitRPC::Util::HashCache::Lazy.new
  end

  class << self
    # Global default timeout for all GitRPC connections. This is the same as
    # passing the :timeout option to GitRPC.new
    #
    # This will be overridden if you pass a timeout option to GitRPC.new as well.
    #
    # timeout - seconds (int)
    attr_accessor :timeout

    # Object returned by GitRPC::Backend#host_metadata
    attr_accessor :host_metadata

    # Extra env vars to pass to all native spawns
    attr_accessor :extra_native_env

    # Tracer for tests
    attr_accessor :test_tracer
  end

  # Global default connect timeout for all GitRPC connections. This is the
  # same as passing the :connect_timeout option to GitRPC.new
  #
  # This will be overridden if you pass a connect_timeout option to
  # GitRPC.new as well.
  #
  # connect_timeout - seconds (int)
  class << self
    attr_accessor :connect_timeout
  end

  # Enable gitmon tracking of backend calls.
  class << self
    attr_writer :gitmon_enabled
  end

  # Set max request size for gitrpc
  class << self
    attr_writer :max_request_size
  end
  @max_request_size = Float::INFINITY

  # Repository template directory, used to symlink the hooks directory
  class << self
    attr_accessor :hooks_template
  end

  class << self
    attr_accessor :repository_root
  end

  def self.gitmon_enabled?
    @gitmon_enabled
  end

  def self.max_request_size
    @max_request_size
  end

  # A boolean value representing the default value to be used for feature
  # flags if a flipper backend has not been set. This value should always
  # be 'false' except when running GitRPC tests with the TEST_ALL_FEATURES
  # environment variable set to "1".
  class << self
    attr_accessor :feature_default
  end
  @feature_default = false

  class << self
    attr_writer :local_git_host_name
  end

  def self.local_git_host_name
    @local_git_host_name || "localhost"
  end

  class << self
    attr_writer :optimize_local_access
  end

  def self.optimize_local_access
    @optimize_local_access || false
  end

  # local_access? returns true if the RPC call to the host should be executed
  # locally.  This is mirrored by DGit itself as GitHub::DGit.local_access? but
  # here is based on knowledge that only GitRPC has access to.
  def self.local_access?(host)
    return false unless GitRPC.optimize_local_access

    host&.chomp(".") == GitRPC.local_git_host_name
  end

  # Instrumentation
  # ---------------
  # Various GitRPC components publish instrumentation stats via the instrument
  # method. The instrumenter object may be configured explicitly if needed. By
  # default, ActiveSupport::Notifications is used.
  #
  # Notify for an operation. This is may be called by any GitRPC component to
  # generate an event.
  # Args match ActiveSupport::Notifications.publish API of (name, started, ended, id, payload)
  def self.publish(name, *args)
    @instrumenter.publish("#{name}.gitrpc", *args) unless @instrumenter.nil?
  end

  # Instrument an operation. This is may be called by any GitRPC component to
  # record an instrumentation event.
  #
  # event   - Name of the event as a symbol. The event is published under the
  #           gitrpc namespace automatically.
  # payload - Hash payload for the event. Available keys are based on the event
  #           being published.
  #
  # Returns the result of executing the block.
  def self.instrument(event, payload = {}, &block)
    if @instrumenter
      block ||= proc {}
      @instrumenter.instrument("#{event}.gitrpc", payload, &block)
    elsif block
      block.call(payload)
    end
  end

  def self.instrument_callbacks(event, payload = {})
    if @instrumenter
      instrumenter = @instrumenter.instrumenter

      # state
      queue_time = nil
      instrumentation_handle = nil

      queued_cb = proc do
        queue_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
      begin_cb = proc do
        # Allows tracking the time from where we knew we wanted the data, to when
        # we started actually executing it (sync).
        unless queue_time.nil?
          payload[:time_queued] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - queue_time)
        end

        instrumentation_handle = instrumenter.build_handle("#{event}.gitrpc", payload)
        instrumentation_handle.start
      end
      end_cb = proc do |_promise, value: nil, reason: nil|  # rubocop:disable Lint/UnusedBlockArgument
        unless reason.nil?
          payload[:exception] = [reason.class.name, reason.message]
        end
        instrumentation_handle.finish
      end
    else
      queued_cb = proc {}
      begin_cb = proc {}
      end_cb = proc {}
    end
    [queued_cb, begin_cb, end_cb]
  end

  # The object that receives instrument messages. This is AS::Notifications by
  # default but may be set to any object that responds to #instrument.
  #
  # Returns an object that responds to #instrument or nil if no instrumentation
  # backend is configured.
  def self.instrumenter
    @instrumenter
  end

  # Configure the instrumentation backend that will receive events. The object
  # must respond to #instrument.
  def self.instrumenter=(object)
    @instrumenter = object
  end

  # Checks if a feature flag is enabled. This is may be called by any GitRPC
  # component.
  #
  # feature_name - Name of the feature flag.
  #
  # Returns true if the flipper backend is set and the feature flag is enabled,
  # otherwise it returns the value of GitRPC.feature_default.
  def self.feature_enabled?(feature_name)
    return @feature_default unless self.flipper

    defined?(self.flipper[feature_name]) && self.flipper[feature_name].enabled?
  end

  # The object that checks if a feature flag is enabled.
  #
  # Returns an object that can be index by a feature name and returns an object
  # that responds to #enabled?. If no flipper backend is set, it returns
  # GitHub.flipper, if it's defined.
  def self.flipper
    if @flipper.nil? && defined?(GitHub.flipper)
      @flipper = GitHub.flipper
    else
      @flipper
    end
  end

  # Configure the flipper backend that will check if a feature flag is enabled.
  def self.flipper=(object)
    @flipper = object
  end

  # Returns a rack app which implements the twirp protocol
  def self.rack_app
    server_svc = ::Spokes::Backend::HealthService.new(HealthHandler.new)
    GitRPC::Twirp::Middleware.setup_for(server_svc, require_repo: false)


    git_svc = ::Spokes::Backend::GitService.new(GitHandler.new)
    GitRPC::Twirp::Middleware.setup_for(git_svc)

    Rack::Builder.new do
      use GitRPC::Twirp::Middleware::BackendMiddleware
      use GitRPC::Twirp::Middleware::GitmonMiddleware
      use GitRPC::Twirp::Middleware::TimeoutMiddleware
      run Rack::Cascade.new([server_svc, git_svc])
    end
  end
end
