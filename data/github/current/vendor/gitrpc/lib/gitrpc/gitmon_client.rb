# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "json"
require "yaml"

module GitRPC
  class GitmonClient
    class Error < StandardError; end
    class AbortError < Error
      def initialize(reason)
        @reason = reason
      end
    end

    # Don't track these calls with gitmon
    #
    # spawn_git will already be tracked by gitmon with git itself
    # The others are very fast (Avg 99-%ile below 1ms over the past month)
    DO_NOT_TRACK = %w{spawn_git online? remove fs_exist? config_get loadavg Online Remove FsExist ConfigGet Loadavg}
    ALWAYS_TRACK = %w{rebase Rebase gitbackups_perform gitbackups_restore}
    # This is the list of calls that will be subject to `fail-fast` throttling
    # when the `throttle_expensive_gitrpc_calls` feature is enabled for a repository network.
    FAIL_FAST_CALLS = %w{alternative_read_diff_pairs_with_base read_diff_pairs_with_base rebase rebase_tmp_objdir_experiment stage_signed_merge_commit persist_signed_merge_commit}

    SOCKET_READ_TIMEOUT=1 # 1 s
    SOCKET_WRITE_TIMEOUT=0.25 # 250 ms

    @@default_socket_path_last_updated = Time.now - 5
    @@default_socket_path = nil

    # Connect to either Governor or Gitmon depending on the existence of the feature flag.
    def self.default_socket_path
      now = Time.now
      if Time.now - @@default_socket_path_last_updated > 5
        if File.exist?("/etc/github/enable-governor")
          @@default_socket_path = "/run/governor/client.sock"
        else
          @@default_socket_path = "/var/run/gitmon/gitstats.sock"
        end
        @@default_socket_path_last_updated = now
      end
      @@default_socket_path
    end

    def self.connect(socket_path = self.default_socket_path)
      if File.socket?(socket_path)
        sock = Socket.new(Socket::AF_UNIX, Socket::SOCK_STREAM)
        sa = Socket.sockaddr_un(socket_path)
        sock.connect_nonblock(sa)
        self.new(sock)
      end
    rescue StandardError
      return nil
    end

    def self.track(backend, method_name, &block)
      if track_method?(method_name, backend) && client = self.connect
        client.track(backend, method_name, &block)
      else
        yield
      end
    end

    def self.track_method?(name, backend)
      opts = backend.options
      if opts[:should_throttle_gitrpc]
        if FAIL_FAST_CALLS.include?(name.to_s)
          backend.fail_fast = "fail-fast"
          return true
        end
      end

      return false if DO_NOT_TRACK.include?(name.to_s)
      return true  if ALWAYS_TRACK.include?(name.to_s)

      case percent = GitRPC.gitmon_enabled?
      when true
        true
      when Integer, Float
        rand < percent.to_f / 100
      else
        false
      end
    end

    def process_data(backend, message)
      info = {
        program: message,
        git_dir: backend.path,
        via: "gitrpc",
      }
      info.update(repo_name: backend.nwo) if backend.nwo
      if dotcom_info = backend.options[:info]
        if dotcom_info.key?(:from)
          info[:from] = dotcom_info[:from]
        end

        if dotcom_info.key?(:repo_id)
          info[:repo_id] = dotcom_info[:repo_id]
        end

        if dotcom_info.key?(:real_ip)
          info[:real_ip] = dotcom_info[:real_ip]
        end

        if dotcom_info.key?(:user_id)
          info[:user_id] = dotcom_info[:user_id]
        end

        if dotcom_info.key?(:request_id)
          info[:request_id] = dotcom_info[:request_id]
        end

        if backend.options[:should_throttle_gitrpc]
          if backend.fail_fast
            info[:qos] = backend.fail_fast
          end
        end
      end
      info
    end

    def track(backend, message, &block)
      update(process_data(backend, message))

      schedule
      begin
        track_stats(backend.options[:should_throttle_gitrpc]) do
          @result = yield if block_given?
        end
      rescue GitmonClient::Error
        # Don't report gitmon errors to gitmon
        raise
      rescue => boom
        error(boom)
        raise
      else
        finish
      end
      result
    ensure
      socket.close
    end

    def initialize(socket, system_stats = SystemStats)
      @socket = socket
      # Will be overwritten when we track stats
      @tracked_stats = {}
      @system_stats = system_stats
    end
    attr_reader :socket, :result, :tracked_stats

    def update(data)
      request("update", data: data)
    end

    def schedule
      response = request("schedule", response_expected: true)
      raise AbortError.new(response) if response && response =~ /^fail/
    end

    def finish
      request("finish", data: tracked_stats.merge(result_code: 0))
    end

    def error(boom)
      request("finish", data: tracked_stats.merge(fatal: boom.class, result_code: 1))
    end

    def request(cmd, data: {}, response_expected: false)
      return nil unless socket

      if ready_for_write?(socket)
        socket.puts(JSON.dump({"command" => cmd, "data" => data}))
      else
        return false
      end

      if response_expected
        if ready_for_read?(socket)
          socket.gets
        else
          false
        end
      end
    rescue StandardError
      # Error talking to gitmon, just continue
      return nil
    end

    def ready_for_read?(socket)
      if socket.is_a? IO
        r, w, e = IO.select([socket], [], [], SOCKET_READ_TIMEOUT)
        !!r
      else
        true
      end
    end

    def ready_for_write?(socket)
      if socket.is_a? IO
        r, w, e = IO.select([], [socket], [], SOCKET_WRITE_TIMEOUT)
        !!w
      else
        true
      end
    end

    def track_stats(should_throttle_gitrpc)
      start_cpu = if should_throttle_gitrpc
        @system_stats.cpu_time_with_children
      else
        @system_stats.cpu_time
      end

      start_read, start_write = @system_stats.disk_stats

      yield

    ensure
      # This is an ensure block so that even if the underlying git operation
      # fails (time out or whatever) we still track our stats.
      end_cpu = if should_throttle_gitrpc
        @system_stats.cpu_time_with_children
      else
        @system_stats.cpu_time
      end
      end_read, end_write = @system_stats.disk_stats

      @tracked_stats = {
        cpu:              ((end_cpu - start_cpu) * 1000).to_i,
        disk_read_bytes:  end_read - start_read,
        disk_write_bytes: end_write - start_write,
      }
    end

    class SystemStats
      def self.disk_stats
        return [0, 0] unless RUBY_PLATFORM =~ /linux/i

        proc_io = File.open("/proc/self/io") { |f|
          # procfs re-renders files on every read(2) invocation, so to ensure a
          # consistent view of proc data, we need to make sure we only invoke
          # read(2) once. see github/github#45079.
          f.sysread(4096)
        }

        io = YAML.load(proc_io)

        [
          io["read_bytes"],
          io["write_bytes"] - io["cancelled_write_bytes"]
        ]
      end

      def self.cpu_time
        Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
      end

      def self.cpu_time_with_children
        times = Process.times
        times.utime + times.stime + times.cutime + times.cstime
      end
    end
  end
end
