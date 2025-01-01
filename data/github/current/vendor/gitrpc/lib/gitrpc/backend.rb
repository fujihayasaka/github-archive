# rubocop:disable Style/FrozenStringLiteralComment
require "time"
require "digest/sha2"
require "rugged"
require "set"

require "ernicorn"
require "gitrpc"
require "gitrpc/hash_algorithm"
require "gitrpc/timer"
require "gitrpc/util"

module GitRPC
  # The Backend has local machine access to repositories on disk. Latency between
  # operations is entirely due to disk access and local cpu time. No network
  # operations are performed at this level.
  #
  # Unlike GitRPC::Client, Backend objects have direct access to the
  # Rugged::Repository. Rugged access methods should be used to implement as
  # many operations as possible.
  #
  # The files in gitrpc/backend/*.rb are automatically loaded when this class
  # is loaded. Each file adds one or more RPC call method implementations. No
  # RPC call methods are defined as part of this file.
  #
  # Documentation on backend RPC call implementations is kept light. The Client
  # side methods are documented thoroughly.
  class Backend
    # git-diff-tree options to detect renames limited to up to 400
    # rename/copy targets.
    DIFF_TREE_DETECT_RENAMES = ["-M", "-l400"]

    # Exit code that git returns when gitmon asks it to abort.  Used for
    # deciding whether or not to throw a CommandBusy exception.
    GITMON_BUSY = 75

    GITMON_INT_PREFIX = "uint:"
    GITMON_STRING_PREFIX = ""

    # Full path to the git repository on disk as a string.
    attr_reader :path

    # Execution options hash. May include the following members:
    #
    # :timeout           - Number of seconds that a request may take.
    # :max               - Total number of bytes that native commands can
    #                      generate.
    # :env               - Hash of environment variables to set for native
    #                      commands.
    # :alternates        - Array of alternate object directory paths.
    #
    # See the GitRPC module docs on OPTIONS for more information.
    attr_reader :options

    # Indicate to gitmon that the call should fail immediately,
    # when the quotas are maxed out.
    attr_accessor :fail_fast

    # Create a new Backend for a git repository. No actual disk access should
    # occur during initialization.
    #
    # path    - Full path to the git repository to access as a string.
    # options - Runtime options provided to the backend. See the GitRPC
    #           module's OPTIONS docs for more info on possible values.
    #
    # Raises nothing. It should be possible to create Backend objects without
    # fear of exceptions due to access problems.
    def initialize(path, options = {})
      @path = path
      @options = options
      @native = nil
      @rugged = nil
      @fail_fast = nil
      @hash_algo = nil

      @options[:trace2] = Array(@options[:trace2])
    end

    # Full path to the network on disk
    def network_path
      Dir.dirname(path)
    end

    @readers, @writers, @cache_writers, @rpc_calls, @writers_with_varying_output, @writers_require_unanimous, @long_running = [].to_set, [].to_set, [].to_set, [].to_set, [].to_set, [].to_set, [].to_set
    @path_exempt = Set.new
    class << self
      attr_reader :readers, :writers, :cache_writers, :writers_with_varying_output, :writers_require_unanimous, :rpc_calls, :path_exempt, :long_running
    end

    def readers
      self.class.readers
    end

    def writers
      self.class.writers
    end

    def cache_writers
      self.class.cache_writers
    end

    def rpc_calls
      self.class.rpc_calls
    end

    def path_exempt
      self.class.path_exempt
    end

    def self.rpc_reader(name, no_git_repo: false, long_running: false)
      @readers << name
      @rpc_calls << name

      if no_git_repo
        @path_exempt << name
      end

      if long_running
        @long_running << name
      end
    end

    def self.rpc_writer(name, output_varies: false, no_git_repo: false, require_unanimous: false, long_running: false)
      @writers << name
      @rpc_calls << name

      if output_varies
        @writers_with_varying_output << name
      end
      if require_unanimous
        @writers_require_unanimous << name
      end
      if no_git_repo
        @path_exempt << name
      end
      if long_running
        @long_running << name
      end
    end

    def self.rpc_cache_writer(name, output_varies: false, no_git_repo: false, require_unanimous: false, long_running: false)
      @cache_writers << name
      @rpc_calls << name

      if output_varies
        @writers_with_varying_output << name
      end
      if require_unanimous
        @writers_require_unanimous << name
      end
      if no_git_repo
        @path_exempt << name
      end
      if long_running
        @long_running << name
      end
    end

    def self.rpc_reader?(name)
      readers.include?(name)
    end

    def self.rpc_writer?(name)
      writers.include?(name)
    end

    def self.rpc_cache_writer?(name)
      cache_writers.include?(name)
    end

    def self.path_exempt?(name)
      path_exempt.include?(name)
    end

    def self.rpc_call?(name)
      rpc_calls.include?(name)
    end

    def self.output_varies?(name)
      writers_with_varying_output.include?(name)
    end

    def self.require_unanimous?(name)
      writers_require_unanimous.include?(name)
    end

    def self.long_running?(name)
      long_running.include?(name)
    end

    # Public: Send a message to the backend. This is provided as a chokepoint
    # for logging and instrumentation. All messages received via RPC or
    # originating from GitRPC::Client elsewise arrive through this method,
    # making it a good place for general error handling and whatnot as well.
    #
    # message - The name of the method to invoke on the backend as a symbol.
    # args    - Zero or more arguments to pass to the method. This must consist
    #           of only primitive types and hashes should use string keys.
    # kwargs  - Zero or more keyword arguments to pass to the method. This must
    #           consist of only primitive types, and hashes should use string
    #           keys.
    #
    # Returns whatever. Results must consist of only primitive types: arrays,
    # hashes with string keys, and scalars.
    #
    # Raises GitRPC::Timeout when the operation takes longer than the configured
    # timeout option in seconds. There is no timeout by default.
    #
    # Raises GitRPC::BadRepositoryState when the operation results in an error
    # that indicates that the repository is in a messed up state.
    def send_message(message, *args, **kwargs)
      message = reroute_rpc_alternatives(message)
      enforce_repository_existence(message)
      GitmonClient.track(self, message) do
        timeout message_timeout do
          if Backend.rpc_call?(message)
            if args && kwargs.any?
              __send__(message, *args, **kwargs)
            elsif kwargs.any?
              __send__(message, **kwargs)
            else
              __send__(message, *args)
            end
          else
            raise NoMethodError.new("Undefined method #{message}")
          end
        end
      end
    rescue Timer::Error => boom
      error = GitRPC::Timeout.new("#{message} - #{boom.message}")
      error.set_backtrace(boom.backtrace)
      Ernicorn.filter_backtrace(error)
      raise error
    rescue Rugged::InvalidError => boom
      error = GitRPC::BadRepositoryState.new("#{message} - #{boom.message}")
      error.set_backtrace(boom.backtrace)
      Ernicorn.filter_backtrace(error)
      raise error
    end

    # Public: Amount of time to wait before halting a send_message invocation.
    # This value is fudged slightly higher than the timeout passed to @native
    # so that backtraces come from deeper in the stack. See GitRPC::Timer for
    # the fudge config.
    #
    # Returns a float number of seconds.
    def message_timeout
      GitRPC::Timer.fudge(options[:timeout], :spawn)
    end

    def enforce_repository_existence(message)
      return if path_exempt.include?(message)

      # If it exists, no problem
      return if Dir.exist?(path)

      id = path.sub(%r[^.*/(\d+)\.git], '\1')

      raise InvalidRepository.new("repository #{id} not found")
    end

    # Sometimes we want an experimental version of an rpc call. When the
    # experiment concludes, we want to safely delete the old or new version.
    # "Safe" in this context means specifically avoiding mismatched servers and
    # clients during a deploy. One method is to do multiple deploys, rolling
    # out the change in phases, but that's tedious.
    #
    # This is a simple mechanism to avoid that: a call to a message prefixed
    # with "alternative_" that doesn't exist is simply redirected to the
    # non-prefixed version. This makes it safe to do an all-at-once deployment
    # - clients that call removed backend experiments just get the non-prefixed
    # version instead.
    def reroute_rpc_alternatives(message)
      if message.start_with?("alternative_") && !Backend.rpc_call?(message)
        return message[12..].to_sym
      end
      return message
    end

    # All common internal utility functions are available to backend call
    # implementations. Also include the Timer lib for timeouts.
    include GitRPC::Util
    include GitRPC::Timer

    # Internal: A Rugged::Repository object attached to the repository's path.
    # All backend method implementations should use this method to access
    # rugged. Creation of the Rugged object is delayed until first use so that
    # Backend objects may be initialized without
    #
    # Returns the Rugged::Repository object.
    # Raises GitRPC::InvalidRepository when the repository directory does not
    # exist or is malformed.
    def rugged
      @rugged ||= Rugged::Repository.bare(path, alternate_object_paths)
    rescue Rugged::OSError, Rugged::RepositoryError
      raise GitRPC::InvalidRepository, $!
    end

    # Internal: A GitRPC::Native object for spawning commands. This is
    # configured with the environment settings given in options.
    #
    # Returns a GitRPC::Native object for executing commands.
    def native
      @native ||= GitRPC::Native.new(path, native_env, native_options)
    end

    # Internal: A GitRPC::HashAlgorithm object appropriate for the current
    # repository.
    #
    # Returns a GitRPC::HashAlgorithm object for determining the properties of
    # the hash algorithm.
    def hash_algo
      return @hash_algo if @hash_algo
      res = checked_spawn_git!("rev-parse", ["--show-object-format"])
      @hash_algo = GitRPC::HashAlgorithm.from_sym(res["out"].chomp)
    end

    # Public: Cleanup the data allocated by the backend.
    # Right now this only closes the Rugged repository that has been opened.
    def cleanup
      @rugged.close if @rugged
      @rugged = nil
    end

    # Internal: Options to pass to the GitRPC::Native object. These can actually
    # be any of the process-spawn options but only a limited subset is supported.
    #
    # Returns an options hash.
    def native_options
      [:timeout, :max].inject({}) do |hash, key|
        hash[key] = options[key] if options.key?(key)
        hash
      end
    end

    # Internal: The native command spawning environment hash. This always
    # includes GIT_DIR and may include GIT_ALTERNATE_OBJECT_DIRECTORIES when
    # a :alternates option was provided.
    #
    # Returns a hash of { string => string } values.
    def native_env
      env = (options[:env] || {}).dup
      env.merge!(GitRPC.extra_native_env || {})
      env["GITHUB_TELEMETRY_LOGS_NOOP"] = "true"
      env["GIT_DIR"] = path
      env["GIT_LITERAL_PATHSPECS"] = "1"
      env["GIT_SOCKSTAT_VAR_via"] = "gitrpc"
      if options[:info]
        git_sockstat_var_options.each do |(prefix, sym)|
          env["GIT_SOCKSTAT_VAR_#{sym}"] = "#{prefix}#{options[:info][sym]}" if options[:info][sym]
        end
      end
      if alternates = alternate_object_paths
        env["GIT_ALTERNATE_OBJECT_DIRECTORIES"] = alternates.join(":")
      end
      env
    end

    # Internal: List of alternate object directories that should be in effect
    # for all git operations. Expands relative paths in options[:alternates].
    #
    # Returns an array of fully expanded alternate object path strings or nil
    # when no alternate object paths were given.
    def alternate_object_paths
      paths = options[:alternates]
      return if paths.nil? || paths.empty?
      paths.map do |path|
        if path.start_with?("/")
          path
        else
          File.expand_path(path, self.path)
        end
      end
    end

    # Public: return a Boolean indicating whether or not there are
    # trace2-related configuration(s) and/or environment variable(s) specific to
    # running trace2 for a given command.
    #
    # command - The name of the git command being run (e.g., 'status', etc)
    #
    # Returns a boolean.
    def trace2_enabled?(command)
      options[:trace2].include?(command.to_sym)
    end

    # RPC method implementations are split up into separate files for
    # organization purposes. The test file structure mirrors this.
    Dir[File.expand_path("../backend/*.rb", __FILE__)].each do |file|
      name = File.basename(file, ".rb")
      require "gitrpc/backend/#{name}"
    end

    # Default repository scope cache key. We take the SHA256 of the path as a
    # good guess. See GitRPC::Protocol for more information on this method.
    def repository_key
      Digest::SHA256.hexdigest(path)
    end

    # Default network scope cache key. We take the SHA256 of the network path as a
    # good guess. See GitRPC::Protocol for more information on this method.
    def network_key
      Digest::SHA256.hexdigest(network_path)
    end

    # Each array element represents a pair whose first element is the prefix
    # Gitmon expects for the data type represented by the second element in the pair,
    # pointed to by the symbol we extract from the rpc options the client passed to the backend.
    def git_sockstat_var_options
      [
        [GITMON_STRING_PREFIX, :real_ip],
        [GITMON_STRING_PREFIX, :repo_name],
        [GITMON_STRING_PREFIX, :request_id],
        [GITMON_INT_PREFIX, :user_id],
        [GITMON_INT_PREFIX, :repo_id]
      ]
    end
  end
end
