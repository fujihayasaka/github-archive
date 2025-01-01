# rubocop:disable Style/FrozenStringLiteralComment
module GitRPC
  class Protocol
    class ChimneyTransitional < Protocol
      CONNECTION_RETRY_LIMIT = 10
      CONNECTION_RETRY_WAIT  = 100

      attr_reader :host, :path, :backend

      def initialize(url, options = {})
        @host = url.host
        @path = url.path

        if GitRPC.local_access?(host)
          @backend = ::GitRPC::Protocol.resolve("file:#{path}", options)
        else
          @backend = ::GitRPC::Protocol.resolve("bertrpc://#{host}#{path}", options)
        end

        @connection_retries = 0
      end

      def options
        @backend.options
      end

      def send_message(message, *args, **kwargs)
        message = message.to_sym

        return false   if message == :exist? && (!host || host == "")
        return online? if message == :online?

        if online?
          res = GitRPC.instrument(:server_remote_call, :host => host, :path => path) do
            backend.send_message(message, *args, **kwargs)
          end
          if @connection_retries > 0
            GitRPC.instrument(:connect_retry_success, :retries => @connection_retries)
            @connection_retries = 0
          end
          res
        else
          GitRPC.instrument(:server_offline, :host => host, :path => path)
          raise ::GitRPC::RepositoryOffline.new(host, path)
        end
      rescue ::GitRPC::ConnectionError, ::GitRPC::NetworkError
        if @connection_retries < CONNECTION_RETRY_LIMIT
          sleep CONNECTION_RETRY_WAIT / 1000.to_f
          @connection_retries += 1
          retry
        else
          GitRPC.instrument(:connect_failure, :retries => @connection_retries)
          @connection_retries = 0
          raise
        end
      end

      def async_send_message(message, *args, **kwargs)
        Promise.resolve.then do
          send_message(message, *args, **kwargs)
        end
      end

      def online?
        return false unless host
        return true if GitRPC.local_access?(host)

        shard_status = self.class.shard_status

        partition = self.extract_partition_from_path(path)
        shard = "#{host}:#{partition}"
        if (status = shard_status[shard]) && (Time.now - status[:time]) < 10.0
          status[:online]
        else
          GitRPC.instrument :online_check, :host => host, :path => path do
            online = ::GitHub::DGit::Util::is_online?(host)
            shard_status[shard] = { :time => Time.now, :online => online }
            online
          end
        end
      end

      # Internal: A hash of status information about each shard across all hosts.
      # Keys are "<host>:<partition>" strings. Values are hashes with :time and
      # :online keys; :time is the last time a real redis check was performed;
      # :online is the boolean result of the check.
      #
      # This table is shared by all GitRPC::Client instances. It's not
      # thread-safe.
      def self.shard_status
        @shard_status ||= {}
      end

      # Extract the partition from a path name. This looks for the first
      # occurrence of a single [0-9a-f] character between two slashes.
      #
      # Returns the partition as a single character String, or nil when no partition
      # exists in the path.
      def extract_partition_from_path(path)
        if path.size == 1
          path
        elsif path =~ /\/([0-9a-f])\//
          $1
        end
      end
    end
  end
end
