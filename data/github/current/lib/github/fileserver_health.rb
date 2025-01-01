# typed: false
# frozen_string_literal: true

require "bertrpc"
require "gitrpc"
require "yajl"
require "github/parallel_rpc"

module GitHub
  module FileserverHealth
    include ParallelRpc
    extend self

    def parallel_rpc(fileservers, command, args: [], kwargs: {})
      super(fileservers, command, args: args, kwargs: kwargs, timeout: 4, connect_timeout: 2)
    end

    def short_host(name)
      if GitHub.enterprise?
        name
      else
        name.sub(/\Agithub-(\w+?)[ab]?-cp1-prd(?:\..*)?\z/, '\1')
            .sub(/\Agithub-(\w+-\w+)(?:\..*)?\z/, '\1')
      end
    end

    def fmt_pct(val)
      val ? ("%d%%" % val) : ""
    end

    def get_fs
      GitHub::DGit.get_fileservers(online_only: true)
    end

    def single_ghe_instance_rpc(_, command)
      host = "localhost"
      backend = ::GitRPC::Protocol.resolve("fakerpc:#{host}")
      answer = backend.send_message(command)
      [host, answer]
    end

    GITMON_PORT = 4486
    def parallel_gitmon(fileservers, command, args)
      fileservers = [GitHub::DGit::Fileserver.standin("localhost")] if Rails.env.development? || Rails.env.test?
      line = Yajl::Encoder.encode({ "command" => command }.merge(args))
      answers = {}
      errors = {}
      sock = Hash[fileservers.map do |fs|
        begin
          h = fs.ip || fs.name
          addrinfo = Addrinfo.getaddrinfo(h, GITMON_PORT, Socket::AF_INET, Socket::SOCK_STREAM).first
          s = Socket.new(addrinfo.afamily, addrinfo.socktype)
          s.connect_nonblock(addrinfo.to_sockaddr)
        rescue SocketError
          next
        rescue Errno::EINPROGRESS
        end
        [s, fs.name]
      end.compact]
      writers = sock.keys
      readers = []
      while readers.any? || writers.any?
        readable, writable = IO.select(readers, writers, nil)

        writable.each do |s|
          begin
            s.puts line
            readers << s
          rescue Errno::EPIPE, Errno::ECONNREFUSED   # connection failed
          end
          writers.delete(s)
        end

        readable.each do |s|
          begin
            str = s.read
            obj = Yajl::Parser.new.parse(str)
            answers[sock[s]] = [
              10 * obj["cpu_health"], 10 * obj["memory_health"], 10 * obj["ernicorn_health"]
            ] if !obj.nil?
            s.close
            readers.delete(s)
          rescue Yajl::ParseError, IOError => e
            errors[sock[s]] = e
          end
        end
      end

      [answers, errors]
    end

    #
    # Gets disk free space info across the given set of hosts and
    # returns a hash looking like:
    #
    #   {
    #     "host1" => [free_space_mb, total_space_mb],
    #     "host2" => [free_space_mb, total_space_mb],
    #     ...
    #     "hostN" => [free_space_mb, total_space_mb],
    #   }
    #
    # describing space on the filesystem containing GitHub.repository_root
    # on each host.
    #
    def get_df_stats(fileservers)
      if GitHub.single_instance? || (GitHub.enterprise? && Rails.env.test?)
        answers = [single_ghe_instance_rpc(fileservers, :disk_free_space)]
      else
        answers, _ = parallel_rpc(fileservers, :disk_free_space)
      end

      Hash[answers]
    end

    #
    # Returns a Hash looking like:
    #
    #   {
    #     "host1" => percent_free_space_bytes,
    #     "host2" => percent_free_space_bytes,
    #     ...
    #     "hostN" => percent_free_space_bytes,
    #   }
    #
    def get_disk_stats(fileservers)
      df_stats = get_df_stats(fileservers)

      slack_space_mb = GitHub.shard_slack_space / 1024
      Hash[
        df_stats.map do |host, freeinfo|
          free_space_mb, total_space_mb = freeinfo
          f = (free_space_mb - slack_space_mb).to_f / (total_space_mb - slack_space_mb)
          [host, [0, f].max]
        end
      ]
    end

    def get_loadavg(fileservers)
      answers, _ = parallel_rpc(fileservers, :loadavg)
      Hash[arr = answers.map do |host, loadavgs|
        [host, loadavgs.max]
      end.compact]
    end

    def get_cpu_count(fileservers)
      answers, _ = parallel_rpc(fileservers, :cpu_count)
      answers
    end

    def get_git_op_count(fileservers)
      answers, _ = parallel_rpc(fileservers, :git_operations_running)
      answers
    end

    def get_repo_replica_count(fileservers)
      answers, _ = parallel_rpc(fileservers, :replica_count, args: [{ repos_only: true }])
      answers
    end

    def get_gist_replica_count(fileservers)
      answers, _ = parallel_rpc(fileservers, :replica_count, args: [{ gists_only: true }])
      answers
    end
  end
end
