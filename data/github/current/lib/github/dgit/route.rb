# typed: true
# frozen_string_literal: true

module GitHub
  class DGit
    # Quacks like a GitRPC::Protocol::DGit::Route.
    class Route
      DEV_PORTS = (8149..8168).to_a.freeze

      # Internal. See Fileserver#to_route.
      def initialize(fileserver, path, ports: nil, read_weight: nil, quiescing: false, healthy: true)
        @fileserver = fileserver
        @path = path
        @dev_ports = ports
        @read_weight = read_weight
        @quiescing = quiescing
        @healthy = healthy
        modify_routes_for_development!
      end

      # The fileserver object associated with this route.
      attr_reader :fileserver

      # The read weight of this route, if it came from a GitHub::DGit::Replica
      attr_reader :read_weight

      # Whether the route is on a fileserver that's quiescing or not
      attr_reader :quiescing

      # Whether the route is for a healthy replica (from GitHub::DGit::Replica)
      attr_reader :healthy

      # Builds a one-off RPC, usually for maintenance.
      # Normal app traffic should use a dgit delegate and GitRPC's dgit protocol.
      def build_maint_rpc
        ::GitHub::DGit::Util.make_gitrpc(rpc_url)
      end

      # The URL to use for GitRPC connections.
      def rpc_url
        if GitHub::DGit.local_access? host
          "file:#{path}"
        elsif Rails.env.development? || Rails.env.test?
          "fakerpc:#{path}" # path has already been modified for dev
        else
          "bertrpc://#{resolved_host}:#{port}#{path}" # path has already been modified for dev
        end
      end

      # The remote_url, for repo->repo transfers
      def remote_url
        if GitHub::DGit.local_access?(host)
          path
        elsif host == "localhost" && (Rails.env.development? || Rails.env.test?)
          # This special-case should be deprecated. At present there is no
          # development/test SSH server so we must do local access.
          path
        else
          "#{resolved_host}:#{path}"
        end
      end

      def rsync_url
        if GitHub::DGit.local_access?(host)
          "#{path}/"
        elsif host == "localhost" && (Rails.env.development? || Rails.env.test?)
          # This special-case should be deprecated. At present there is no
          # development/test SSH server so we must do local access.
          "#{path}/"
        else
          "git@#{resolved_host}:#{path}/"
        end
      end

      # Sort to avoid dining philosophers.
      def <=>(other)
        # Sort healthy replicas before unhealthy, and
        # voting replicas before nonvoting replicas:
        [@healthy ? 0 : 1, voting? ? 0 : 1, host, port] <=> [other.healthy ? 0 : 1, other.voting? ? 0 : 1, other.host, other.port]
      end

      def ==(other)
        original_host == other.original_host &&
        host == other.host &&
        port == other.port &&
        path == other.path
      end
      alias_method :eql?, :==

      def hash
        original_host.hash ^ port.hash
      end

      # The route's fileserver's name, according to the database
      def original_host
        fileserver.name
      end

      # The route's fileserver hostname.
      #
      # In dev/test, dgitX is changed to localhost. Everywhere else
      # this is the same as original_host.
      def host
        @host || original_host
      end
      attr_writer :host

      # The route's fileserver fqdn.
      #
      # In dev/test, dgitX is changed to localhost. Everywhere else this reflects
      # the fqdn recorded in the fileservers table
      def fqdn
        @fqdn || fileserver.fqdn
      end
      attr_writer :fqdn

      # Return the most specific thing possible that we can connect to.
      #
      # Order of preference goes like this:
      # * IP address
      # * fqdn
      # * host
      def resolved_host
        fileserver.ip || fqdn || host
      end

      def datacenter
        fileserver.datacenter
      end

      def voting?
        fileserver.contains_voting_replicas?
      end

      # Should babeld ignore receive-pack errors when pushing to this route?
      def ignore_recv_errors?
        !voting? || !@healthy
      end

      def cache_server?
        fileserver.cache_server?
      end

      def unreachable?
        fileserver.unreachable?
      end

      def overloaded?
        fileserver.overloaded?
      end

      # The port where ernicorn is listening on the fileserver
      def port
        @port || 8149
      end
      attr_writer :port

      # The path to the repository on disk.
      attr_accessor :path

      private

      def modify_routes_for_development!
        return unless Rails.env.development? || Rails.env.test?

        if host =~ /\Adgit(\d+)/
          @host = "localhost"
          @fqdn = "localhost"
          @port = (@dev_ports || DEV_PORTS)[$1.to_i - 1]
          @path = DGit.dev_route(@path, original_host)
        end
      end
    end
  end
end
