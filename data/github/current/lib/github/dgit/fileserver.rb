# typed: false
# frozen_string_literal: true

module GitHub
  class DGit
    class Fileserver
      # Create something like a fileserver, but without knowing anything
      # about its actual state.
      #
      # This method exists so that #initialize can take the same number
      # of args that GitHub::DGit.get_fileserver_rows pulls from the
      # database, and so that HostPicker can build a one-off fileserver
      # object if it needs to.
      def self.standin(name, ip = nil)
        # For now, this is adequate. In the future, it might make sense
        # to make a Fileserver-like object that raises for some things.
        # Or maybe just mark this fake record embargoed?
        new name: name,
          ip: ip,
          fqdn: nil,
          datacenter: GitHub.default_datacenter,
          rack: GitHub.default_rack,
          online: false,
          embargoed: false,
          evacuating: false,
          voting: true,
          hdd_storage: false
      end

      # Try to load disk stats for an array of Fileservers in parallel.
      def self.prefill_disk_stats(fileservers)
        # Skip any objects that already know their stats
        need_disk_stats = fileservers.select { |fs| fs.instance_variable_get(:@disk_stats).nil? }
        return if need_disk_stats.empty?

        GitHub::DGit.parallel_disk_stats(need_disk_stats).each do |fs, disk_stats|
          fs.instance_variable_set(:@disk_stats, disk_stats)
        end
      end

      def initialize(name:, ip:, fqdn:, datacenter:, rack:, online:, embargoed:, evacuating:, voting:, hdd_storage:, site: nil, cache_location: nil, unreachable: false, overloaded: false)
        @name = name
        @ip = ip
        @fqdn = fqdn
        @datacenter = datacenter
        @rack = rack
        @online = online
        @embargoed = embargoed
        @evacuating = evacuating
        @voting = voting
        @hdd_storage = hdd_storage
        @site = site
        @cache_location = cache_location
        @unreachable = unreachable
        @overloaded = overloaded
      end

      def to_route(path, **opts)
        Route.new(self, path, **opts)
      end

      # Builds a one-off RPC, usually for maintenance.
      # Normal app traffic should use a dgit delegate and GitRPC's dgit protocol.
      def build_maint_rpc(*opts)
        to_route(*opts).build_maint_rpc
      end

      # The hostname of the fileserver
      attr_reader :name

      # The IP address of the fileserver
      attr_reader :ip

      # The FQDN of the fileserver
      attr_reader :fqdn

      # The datacenter where the fileserver is
      attr_reader :datacenter

      # The site where the fileserver is
      attr_reader :site

      # The rack where the fileserver is
      attr_reader :rack

      # The cache location, if this is a cache server (otherwise nil)
      attr_reader :cache_location

      # Whether spokesd experienced problems connecting to a fileserver.
      def unreachable?
        @unreachable
      end

      # Whether the fileserver's load1 is unhealthy.
      def overloaded?
        @overloaded
      end

      # Is the fileserver online, according to the database?
      def online?
        @online
      end

      # Is this fileserver restricted from taking on new replicas?
      def embargoed?
        @embargoed
      end

      # Is this fileserver shedding all of its replicas?
      def evacuating?
        @evacuating
      end

      # Is this fileserver fitted with hard disk drives?
      def hdd_storage?
        @hdd_storage
      end

      def cache_server?
        !@cache_location.nil?
      end

      def ==(other)
        name == other.name &&
          ip == other.ip &&
          fqdn == other.fqdn &&
          datacenter == other.datacenter &&
          rack == other.rack &&
          online? == other.online? &&
          embargoed? == other.embargoed? &&
          contains_voting_replicas? == other.contains_voting_replicas? &&
          hdd_storage? == other.hdd_storage?
      end

      # Get a replica-placement weight for the given host.
      # Currently, this is weighted by available disk space, minus the 10GB
      # of slack space that we try to keep free on every disk.
      #
      # This value may be overridden during allocation.
      #
      # TODO: incorporate long-term load leveling in addition to available
      # disk space.
      def weight
        @weight ||= fraction_of_space_available
      end
      attr_writer :weight

      # Get the fraction of disk space available to repositories.
      #
      # Returns an array with two elements:
      #   - a float between 0.0 and 1.0, the fraction of space available
      #   - the absolute size of the disk in MB
      #
      # See GitHub::DGit.disk_stats for more details.
      def disk_stats
        @disk_stats ||= GitHub::DGit.disk_stats(name, rpc_builder: method(:build_rpc_for_disk_stats)).freeze
      end

      def disk_stats_valid?
        disk_stats != GitHub::DGit::DGIT_DISK_STATS_INVALID
      end

      def fraction_of_space_available
        disk_stats[0]
      end

      def size_of_disk_in_mb
        disk_stats[1]
      end

      def placement_zone
        rack
      end

      # Are replicas on this fileserver considered to be voting
      # replicas?
      def contains_voting_replicas?
        @voting
      end

      private

      def build_rpc_for_disk_stats(path)
        to_route(path).build_maint_rpc
      end
    end
  end
end
