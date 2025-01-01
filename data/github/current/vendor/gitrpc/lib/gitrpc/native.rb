# rubocop:disable Style/FrozenStringLiteralComment
require "tmpdir"
require "open3"
require "progeny"

module GitRPC
  # Execution environment for spawning external commands. This is used primarily
  # to spawn git processes but can also be used for other types of commands.
  #
  # Creating a new instance of this class establishes the defaults for an
  # execution environment but does not actually spawn any commands. This allows
  # things like environment variables and basic spawn options to be established
  # and used for multiple commands.
  class Native
    # Git repository directory. This is set as the working directory for
    # all spawned commands. May also be nil if you really don't want to
    # chdir.
    attr_reader :path

    # The unix environment for the new child process. Keys in this hash
    # must be strings and values must also be strings or nil to unset a
    # variable.
    attr_reader :env

    # Spawn options. The most commonly used options are :input,
    # :timeout, and :max. See the Progeny::Command documentation
    # for more: http://git.io/zzBPmw#L4
    attr_reader :options

    # Create a new execution environment with the default settings provided. See
    # the attributes above for more info.
    def initialize(path, env = {}, options = {})
      @path = path
      @env  = env
      @options = options
    end

    # Low level process spawning interface. Used to spawn any command within the
    # context established in the initializer.
    #
    # argv  - Array of command line arguments. This isn't interpreted by the
    #         shell. The new process's argv is set exactly.
    # input - Input to write to the new process's stdin stream.
    #
    # Returns a Hash containing a lot of information about the completely
    # executed command.
    def spawn(argv, input = nil, env = {}, options = {})
      if env.is_a?(Hash)
        env = @env.merge(env)
      else
        env = @env
      end

      wd = if File.directory?(@path)
        @path
      else
        Dir.tmpdir
      end

      opts = options.dup
      opts.delete(:max) if options.key?(:max) && options[:max].nil?

      options = @options.merge(:chdir => wd, :input => input, :pgroup_kill => true, :noexec => true).merge(opts)
      options[:timeout] = opts[:timeout] || @options[:timeout]
      process = Progeny::Command.new(env, *(argv + [options]))

      truncated = false

      begin
        process.exec!
      rescue ::Progeny::TimeoutExceeded => boom
        # when a timeout is exceeded there could be an scenario where we have not properly waited on the spawned process
        # because it hasn't properly terminated yet.
        # Let's attempt to invoke the waitpid method with the WNOHANG flag again to see if the process has already exited.
        begin
          status = ::Process::waitpid(process.pid, ::Process::WNOHANG)
          if status.nil?
            # the spawned process has not exited, let's make sure we don't leave it as a zombie
            ::Process::detach(process.pid)
          end
        rescue Errno::ECHILD, SystemCallError
        end
        raise boom
      rescue ::Progeny::MaximumOutputExceeded
        # If we specify a max, we still want the output we can get, but set truncated in the response
        truncated = true
      rescue Errno::ENOENT => boom
        if Dir.exist?(@path)
          raise boom
        else
          raise GitRPC::InvalidRepository, "Does not exist: #{@path}"
        end
      end

      {
        # Report unhandled signals as failure
        :ok        => !!process.status.success?,
        # Report the exit status as the signal number if we have it
        :status    => process.status.exitstatus || process.status.termsig,
        :signaled  => process.status.signaled?,
        :pid       => process.status.pid,
        :out       => process.out,
        :err       => process.err,
        :argv      => argv,
        :env       => env,
        :path      => @path,
        :options   => options,
        :truncated => truncated,
      }
    end

    # Low level process creation interface. Use to prepare a command to be
    # run externally - the actual return value will be ready-to-run command.
    # Invoke by running `exec!` on the returned value.
    #
    # XXX timeout argument is a hack until we have per-call timeouts.
    def build(argv, input = nil, env = {}, timeout = nil)
      if env.is_a?(Hash)
        env = @env.merge(env)
      else
        env = @env
      end

      options = @options.merge(:pgroup_kill => true)
      options = options.merge(:chdir => @path, :input => input)
      options = options.merge(:timeout => timeout) if timeout

      Progeny::Command.build(env, *(argv + [options]))
    end

    # A low level process creation interface that returns a PID, a pipe for standard
    # input, and one for standard output.
    def spawn_piped(argv, env = {})
      if env.is_a?(Hash)
        env = @env.merge(env)
      else
        env = @env
      end

      options = @options.merge(:chdir => @path)
      options.delete(:timeout)

      Progeny::Command.spawn_with_pipes(env, *(argv + [options]))
    end


    # Low level process spawning interface. Used to spawn any command within the
    # context established in the initializer. Counts the # of lines from stdout in
    # a buffered/performant way. Useful if you have a lot of output but only care
    # about total line count
    #
    # argv  - Array of command line arguments. This isn't interpreted by the
    #         shell. The new process's argv is set exactly.
    #
    # Returns a Hash containing a lot of information about the completely
    # executed command.
    def spawn_and_count_stdout_lines(argv, env = {})
      begin
        line_count = IO.popen([env, *argv, chdir: @path]) do |stdout|
          stdout.each_line.count
        end

        {
          :ok         => $?.success?,
          :status     => $?.exitstatus,
          :pids       => $?.pid,
          :line_count => line_count,
          :argv       => argv,
          :env        => env,
          :path       => @path,
        }
      rescue Errno::ENOENT => boom
        if Dir.exist?(@path)
          raise boom
        else
          raise GitRPC::InvalidRepository, "Does not exist: #{@path}"
        end
      end
    end
  end
end
