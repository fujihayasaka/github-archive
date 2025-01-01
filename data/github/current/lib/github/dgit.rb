# typed: true
# frozen_string_literal: true

require "github/config/gitrpc"
require "gitrpc/protocol/dgit"
require "github/dgit/constants"
require "github/dgit/error"
require "github/dgit/host_picker"
require "github/dgit/repo_types"
require "github/dgit/states"
require "github/dgit/util"
require "github/config/memcache"
require "github/dns"

module GitHub
  class DGit
    autoload :Delegate,                      "github/dgit/delegate"
    autoload :Maintenance,                   "github/dgit/maintenance"
    autoload :Routing,                       "github/dgit/routing"
    autoload :ThreePhaseCommitClient,        "github/dgit/three_phase_commit_client"
    autoload :SpokesdThreePhaseCommitClient, "github/dgit/three_phase_commit_client"
    autoload :Rebalancer,                    "github/dgit/rebalancer"
    autoload :Replica3PCClient,              "github/dgit/replica_3pc_client"
    autoload :Util,                          "github/dgit/util"
    autoload :ReadWeightAllocator,           "github/dgit/read_weight_allocator"

    # models
    autoload :Fileserver,                    "github/dgit/fileserver"
    autoload :Replica,                       "github/dgit/replica"
    autoload :Route,                         "github/dgit/route"

    # connection management
    autoload :DB,                            "github/dgit/sql"
    autoload :SQL,                           "github/dgit/sql"

    def self.local_access?(host)
      # All use of DGit will make the same choice as GitRPC does for whether to
      # execute operations locally.  This is a separate method to indicate that
      # isn't just about GitRPC but about other ways of touching repositories on
      # disk.
      GitRPC.local_access? host
    end

    # DGit routes in dev are stored in paths like
    #   repositories/development/dgit1/e/nw/ec/cb/c8/3/37.git
    # instead of
    #   repositories/development/e/nw/ec/cb/c8/3/37.git
    def self.dev_route(path, host)
      raise "dev_route called for already dev-mapped path, #{path}" if path =~ /dgit\d/
      if path.start_with?(GitHub.repository_root)
        suffix = path[GitHub.repository_root.length..-1]
        "#{GitHub.repository_root}/#{host}#{suffix}"
      else
        path
      end
    end

    def self.rpc_for_host_path(host, path)
      rpc = if local_access? host
        ::GitRPC.new("file:#{path}")
      elsif GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test?
        ::GitRPC.new("fakerpc:#{GitHub::DGit::dev_route(path, host)}")
      else
        ::GitHub::DGit::Util.make_gitrpc("bertrpc://#{host}#{path}")
      end
      if !rpc.options.has_key? :info
        rpc.options[:info] = {}
      end
      rpc.options[:info][:user_id] = GitHub.context[:actor_id] if GitHub.context[:actor_id]
      rpc.options[:info][:real_ip] = GitHub.context[:actor_ip] if GitHub.context[:actor_ip]
      rpc.options[:info][:request_id] = GitHub.context[:request_id] if GitHub.context[:request_id]
      rpc
    end

    # Return an object that can be used to commit a reference update.
    def self.update_refs_coordinator(repository, priority: :high) # FIXME: un-AR this interface, consume NWO + Delegate directly.
      options = { priority: priority }
      options[:coalesce] = true if repository.coalesce_dgit_updates?
      if request_id = GitHub.context[:request_id]
        options[:request_id] = request_id
      end
      delegate = repository.dgit_delegate_for_update_refs_coordinator
      if GitHub.spokesd_enabled?
        SpokesdThreePhaseCommitClient.new(repository.full_name, delegate, **options)
      else
        ThreePhaseCommitClient.new(repository.full_name, delegate, **options)
      end
    end

    def self.with_dgit_lock(repository, &block)
      tpc = update_refs_coordinator(repository)
      tpc.with_dgit_lock(block)
    end

    # Get all names of fileservers that meet the given criteria.
    def self.get_hosts(**options)
      get_fileservers_rows(**options).map(&:first)
    end

    # Get all hosts that meet the given criteria as Fileserver instances.
    def self.get_fileservers(**options)
      get_fileservers_rows(**options).map do |row|
        Fileserver.new \
          name: row[0],
          ip: row[5],
          fqdn: row[10],
          datacenter: row[1] || GitHub.default_datacenter,
          rack: row[2] || GitHub.default_rack,
          site: row[9],
          online: row[6] == 1,
          embargoed: row[3] == 1,
          evacuating: row[4] == 1,
          voting: row[7] != 1,
          hdd_storage: row[8] == 1,
          cache_location: row[11]
      end
    end

    # Internal.
    def self.get_fileservers_rows(online_only: true, exclude_embargoed: false, in_datacenters: nil, voting_only: false, storage_class: :ssd, server_type: :all)
      raise ArgumentError unless [:hdd, :ssd, :all].include?(storage_class)
      in_datacenters = in_datacenters && Array(in_datacenters)
      in_datacenters_key = in_datacenters ? in_datacenters.join(",") : "any"
      GitHub.cache.fetch("dgit.hosts.v5.#{in_datacenters_key}.#{online_only}.#{exclude_embargoed}.#{voting_only}.#{storage_class}.#{server_type}", ttl: 1.minute) do
        sql = GitHub::DGit::DB::FS::SQL.new <<-SQL
          SELECT host, datacenter, rack, embargoed, evacuating, ip, online, non_voting, hdd_storage, site, fqdn, #{ have_cache_location_column? ? "cache_location" : "NULL" }
          FROM fileservers
            WHERE host != 'localhost'
        SQL

        sql.add "AND online = 1" if online_only
        sql.add "AND embargoed = 0 AND evacuating = 0" if exclude_embargoed
        sql.add "AND datacenter IN :datacenters", datacenters: in_datacenters if in_datacenters
        sql.add "AND non_voting = :non_voting", non_voting: 0 if voting_only
        sql.add "AND hdd_storage = 1 " if storage_class == :hdd
        sql.add "AND hdd_storage = 0 " if storage_class == :ssd
        if have_cache_location_column?
          sql.add "AND cache_location IS NULL " if server_type == :non_cache
          sql.add "AND cache_location IS NOT NULL " if server_type == :cache
        else
          sql.add "AND FALSE " if server_type == :cache
        end

        unless GitHub.single_or_multi_tenant_enterprise?
          pattern = (GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test?) ? "dgit%" : "github-dfs%"
          sql.add <<-SQL, pattern: pattern
            AND host LIKE :pattern
          SQL
        end

        sql.results
      end
    end   # self.get_fileservers_rows

    # Get the fraction of disk space available to repositories.
    # This is:
    #              free_disk_space - slack_disk_space
    #   F = max(0, ----------------------------------- )
    #              total_disk_space - slack_disk_space
    # If we're calling this to place a repository of known size, then
    # subtract that size from the numerator, too.  The idea here is to get
    # a normalized measure of how good an idea it is to move repos onto
    # (or off of) a given host.
    #
    # When F is 0, we need to clear off space.  The higher F is, the more
    # underutilized the disk is, and the more repos we should move onto
    # it.
    #
    # Returns an array with two elements:
    #   - a float between 0.0 and 1.0, the fraction of space available
    #   - the absolute size of the disk in MB
    #
    # If the call fails, return [0, 1] so the host can only be chosen if
    # everyone else also returns zero.
    #
    # Don't run this on a traditional github-fs, where there are 16
    # separate partitions.
    #
    # Optionally accept `rpc_builder`, which is a proc to create a GitRPC
    # object that can talk to the fileserver.
    def self.disk_stats(host, rpc_builder:)
      # We don't think this method is used anymore. Let's report an error if
      # someone calls it to try to track it down.
      if GitHub.flipper[:dgit_disk_stats_report].enabled?
        Failbot.report! ::GitHub::DGit::Error.new("disk_stats method unexpectedly invoked"), app: "github-dgit-debug"
      end

      GitHub.cache.fetch(disk_stats_cache_key(host), ttl: disk_stats_cache_ttl) do
        rpc = rpc_builder.call(GitHub.repository_root)
        interpret_disk_free_space(rpc.disk_free_space)
      end
    rescue SocketError, ::GitRPC::Error
      GitHub::DGit::DGIT_DISK_STATS_INVALID
    end   # self.disk_stats

    class ParallelDiskStatFileserver
      def initialize(fileserver)
        @fileserver = fileserver
      end

      attr_reader :fileserver

      def cache_key
        @cache_key ||= GitHub::DGit.disk_stats_cache_key(fileserver.name)
      end

      def error_cache_key
        @error_cache_key ||= GitHub::DGit.disk_stats_error_cache_key(fileserver.name)
      end

      def rpc_url
        @rpc_url ||= fileserver.to_route(GitHub.repository_root).rpc_url
      end

      attr_accessor :result
    end

    # Public: Get disk stats for a set of fileservers via GitRPC
    #
    # This does not look for stats in memcache. It does cache any results received.
    def self.fill_disk_stats_cache(fileservers: GitHub::DGit.get_fileservers)
      fileservers.each_slice(100) do |slice|
        _parallel_disk_stats(slice.map { |fs| ParallelDiskStatFileserver.new(fs) })
      end
    end

    # Public: Get disk stats for a set of fileservers
    #
    # Try to load disk stats from cache. (Good results and errors are cached.) If
    # there are any servers that don't have cached values, query them directly via
    # GitRPC.
    def self.parallel_disk_stats(fileservers)
      fileserver_disk_stats = fileservers.map { |fs| ParallelDiskStatFileserver.new(fs) }

      # Check in memcached for cached results and errors.
      cached = GitHub.cache.get_multi(fileserver_disk_stats.map(&:cache_key) + fileserver_disk_stats.map(&:error_cache_key))
      need_rpc_call = []
      fileserver_disk_stats.each do |fs|
        if val = cached[fs.cache_key]
          fs.result = val
        elsif !cached[fs.error_cache_key]
          need_rpc_call << fs
        end
      end

      # Load the rest via gitrpc.
      unless need_rpc_call.empty?
        _parallel_disk_stats(need_rpc_call)
      end

      fileserver_disk_stats.map { |fs| [fs.fileserver, fs.result || [0, 1]] }
    end

    # Internal: Request disk stats values in parallel
    #
    # fileserver_disk_stats must be an Array of ParallelDiskStatFileserver objects,
    # or an enumerable object whose elements respond to `rpc_url` and have a read/write
    # attribute `result`.
    def self._parallel_disk_stats(fileserver_disk_stats)
      GitHub.dogstats.time("dgit.parallel_disk_stats") do
        answers, errors = GitHub::DGit::Util.gitrpc_send_multiple(fileserver_disk_stats.map(&:rpc_url), :disk_free_space, [], {}, timeout: 5, connect_timeout: 3)
        fileserver_disk_stats.each do |fs|
          if answer = answers[fs.rpc_url]
            fs.result = interpret_disk_free_space(answer)
            GitHub.cache.set(fs.cache_key, fs.result, disk_stats_cache_ttl)
          elsif error = errors[fs.rpc_url]
            # Let this fall through and get the default value, which will avoid another failed attempt to query disk_stats.
            # Also report it so that systematic problems will get noticed and fixed.
            Failbot.report! error, app: "github-dgit-debug"
            GitHub.cache.set(fs.error_cache_key, true, disk_stats_cache_ttl)
          end
        end
      end
    end

    # Internal. Parses the output of a GitRPC :disk_free_space call.
    def self.interpret_disk_free_space(freeinfo)
      free_space_mb, total_space_mb = freeinfo
      slack_space_mb = GitHub.shard_slack_space / 1024
      f = (free_space_mb - slack_space_mb).to_f / (total_space_mb - slack_space_mb)
      [[0, f].max, total_space_mb]
    end

    # Internal.
    def self.disk_stats_cache_ttl
      GitHub.dgit_disk_stats_cache_ttl
    end

    # Internal.
    def self.disk_stats_cache_key(host)
      "dgit.disk_stats.#{host}"
    end

    # Internal.
    def self.disk_stats_error_cache_key(host)
      "dgit.disk_stats_error.#{host}"
    end

    # Pick hosts on which to place a replica.
    #   count:      the number of hosts to pick.  This would be 1 if creating a
    #               single replica, or DGIT_COPIES if creating or importing a
    #               repo.
    #   exclusions: hosts not to pick.  For example, when evicting a
    #               replica from a host, put that host in this list.  When
    #               creating a new replica for a network, put the existing
    #               hosts for that network here.  When creating or
    #               importing a repo, use [].
    #
    # This function strictly favors hosts not on the same rack/row as
    # other hosts chosen while the function is running, but it is willing
    # to use same-rack/row hosts rather than return failure.
    #
    # This function weights choices by available disk space, but
    # ultimately picks at random.  That is, if choice A has 60GB free and
    # choice B has 120GB free, then choice B is twice as likely.
    #
    # If DNS is not available, this function degrades to random selection.
    # If DNS is slow, this function may take a while, though caching will
    # help.
    def self.pick_hosts(count, exclusions)
      pick_fileservers(count, exclusions).map { |fs| fs.name }
    end

    # Like pick_hosts, but returns Fileserver objects instead of bare strings.
    def self.pick_fileservers(count, exclusions)
      picker = HostPicker.new
      picker.pick_fileservers(count, exclusions: exclusions, far_from: [])
    end

    # Like pick_fileservers, but for non-voting fileservers.
    def self.pick_non_voting_fileservers(count, exclusions)
      fileservers = GitHub::DGit.get_fileservers(exclude_embargoed: true).reject(&:contains_voting_replicas?)
      picker = HostPicker.new
      picker.pick_fileservers(count, exclusions: exclusions, far_from: [], fileserver_pool: fileservers, no_raise: true)
    end

    def self.pick_non_voting_hosts(count, exclusions)
      pick_non_voting_fileservers(count, exclusions).map(&:name)
    end

    # Takes an array of active hosts, candidates for serving reads.
    #
    # Return a mapping of host to read weight for the provided hosts.
    def self.alloc_read_weight(hosts)
      # only consider online fileservers
      online = hosts & DGit.get_hosts
      # if nothing is online, go ahead and use them all, it doesn't matter
      online = hosts if online.empty?
      # simplistic, pick at random
      reader = online[rand(online.size)]
      Hash[hosts.map do |host|
        [host, host == reader ? 100 : 0]
      end]
    end

    OFFLINE_THRESHOLD = 3

    # In CI we can be running on a very busy host which can mean we consider the
    # servers to be overloaded when we're just in test mode. Make the value when
    # testing high enough we wouldn't expect to see it without the host being on
    # fire.
    if GitHub::AppEnvironment.test?
      EMERGENCY_LOADAVG = 10_000
      EMERGENCY_LOADAVG_NEW = 10_000
    else
      EMERGENCY_LOADAVG = 50
      EMERGENCY_LOADAVG_NEW = 100
    end

    # Check to see if a host is probably offline from the point of view of
    # the local host.  That bit is stored in memcache.  It's set when a
    # gitrpc fails to connect (connection refused or timed out).
    #
    # Offline bits in memcache are set with a TTL of 60 seconds, and so
    # are cleared after that amount of time.
    #
    # Enterprise-only: the offline bit may also be set when
    # DGit.liveness_check fails for the host.  It may also be cleared
    # when DGit.liveness_check succeeds for the host.  The liveness_check
    # job is only run for GHE due to limitations on dot com.
    #
    # The host parameter must be the short hostname, from the fileservers
    # table.
    def self.is_route_offline?(host)
      route_offline_count(host) >= OFFLINE_THRESHOLD
    end

    # Mark a host as probably offline, from the point of view of the local
    # host, because an RPC couldn't connect, or a liveness check failed in
    # any way.  This is done with a short timeout in case something
    # happens to the liveness checks.
    #
    # The host parameter must be the short hostname, from the fileservers
    # table.
    #
    # This function is super racy, because there's no lock around the read
    # and write.  I could use GitHub.cache.incr, but it doesn't give me control
    # over the ttl.  The penalty for racing here is pretty small.  Two
    # incrementers at the same time might only increase the count by one.
    # An incrementer racing with a decrementer will go last-write-wins and so
    # may leave the host "offline" even when a check has passed.
    def self.set_route_offline(host, count = 1)
      val = route_offline_count(host) + count
      GitHub.cache.set(route_offline_key(host), val, 1.minute)
      val >= OFFLINE_THRESHOLD
    end

    # Mark a host as back online, from the point of view of the local
    # host.
    #
    # The host parameter must be the short hostname, from the fileservers
    # table.
    def self.set_online(host)
      GitHub.cache.delete(route_offline_key(host))
    end

    # The key name, in memcache, for indicating that a host is unreachable
    # from the local host.
    def self.route_offline_key(host)
      "dgit:offline:#{GitHub.local_host_name_short}:#{host}"
    end
    private_class_method :route_offline_key

    def self.route_offline_count(host)
      (GitHub.cache.get(route_offline_key(host)) || 0)
    end
    private_class_method :route_offline_count

    # Mark the given host as overloaded.
    def self.set_overloaded(host)
      GitHub.cache.set(overloaded_key(host), 1, 1.minute)
    end

    # Return whether the given host has been marked as overloaded.
    def self.is_overloaded?(host)
      ((GitHub.cache.get(overloaded_key(host)) || 0) > 0)
    end

    # Clear whether the given host is marked as overloaded.
    def self.clear_overloaded(host)
      GitHub.cache.delete(overloaded_key(host))
    end

    # The key name, in memcache, for indicating that a host is overloaded.
    def self.overloaded_key(host)
      "dgit:overloaded:#{host}"
    end
    private_class_method :overloaded_key

    # Attempt to contact every DGit host that the fileservers table says
    # is up, even the ones that have their offline key set in memcache.
    # Anything that fails the liveness check sets (or refreshes) the
    # offline key in memcache.  Anything that passes the check clears the
    # offline key.
    # Enterprise-only: in prod we rely on the health status information
    # reported by spokesd's `AllRepoReplicas` endpoi
    LIVENESS_CONNECT_TIMEOUT = 2  # seconds
    LIVENESS_READ_TIMEOUT    = 4  # seconds
    def self.liveness_check(ports: nil)
      # See https://github.com/github/sre-delivery/issues/389: this checker job
      # routine will never be properly supported for GitHub dot com going forward.
      raise "enterprise-only method unexpectedly invoked (#{__method__})" unless GitHub.enterprise?

      fileservers = get_fileservers(storage_class: :all)
      return if fileservers.count(&:contains_voting_replicas?) < 2
      routes = fileservers.map { |fs| fs.to_route("/", ports: ports) }

      up = []
      down = []
      sketchy = []
      start = Time.now
      GitHub.dogstats.time "dgit.liveness_check" do
        handler = ::BERTRPC::MuxHandler.new
        routes.each do |route|
          service = ::BERTRPC::Service.new(route.resolved_host, route.port, LIVENESS_READ_TIMEOUT, LIVENESS_CONNECT_TIMEOUT)
          rpc = service.call.gitrpc
          cs = handler.queue(rpc)
          do_error = proc do |count, metric|
            GitHub.stats.increment "dgit.#{route.original_host}.#{metric}" if GitHub.enterprise?
            GitHub.dogstats.increment("dgit.#{metric}", tags: ["server:#{route.original_host}", "server_datacenter:#{route.datacenter}"])
            if set_route_offline(route.original_host, count)
              down << route.original_host
            else
              sketchy << route.original_host
            end
          end
          cs.on_complete do |result|
            if result[0] > EMERGENCY_LOADAVG
              do_error.call(OFFLINE_THRESHOLD, "rpc-busy")  # mark offline immediately
            else
              set_online(route.original_host)
              up << route.original_host
            end
          end
          cs.on_error do |_raw_error|
            do_error.call(1, "rpc-error")
          end
          rpc.send_message("/", {}, :loadavg, [], {})
        end
        handler.run(LIVENESS_READ_TIMEOUT, LIVENESS_CONNECT_TIMEOUT)
      end

      if GitHub.enterprise?
        prefix = "dgit.#{GitHub.local_host_name_short}.liveness_check"
        GitHub.stats.timing "#{prefix}.timing",   Time.now - start
        GitHub.stats.gauge  "#{prefix}.up",       up.size
        GitHub.stats.gauge  "#{prefix}.sketchy",  sketchy.size
        GitHub.stats.gauge  "#{prefix}.down",     down.size
      end

      GitHub.dogstats.gauge("dgit.liveness_check", up.size,      tags: ["state:up"])
      GitHub.dogstats.gauge("dgit.liveness_check", sketchy.size, tags: ["state:sketchy"])
      GitHub.dogstats.gauge("dgit.liveness_check", down.size,    tags: ["state:down"])
      if !down.empty?
        GitHub.logger.info("found hosts failing liveness check",
                           "code.namespace" => "GitHub::DGit",
                           "code.function" => "liveness_check",
                           "gh.timing.elapsed_seconds" => Time.now - start,
                           "gh.dgit.liveness_check.up_hosts_count" => up.size,
                           "gh.dgit.liveness_check.sketchy_hosts_count" => sketchy.size,
                           "gh.dgit.liveness_check.down_hosts_count" => down.inspect)
      end

      down
    end

    # Any datacenter with non-embargoed HDD-class storage servers is considered
    # eligible for cold storage
    def self.cold_storage_dcs
      get_fileservers(exclude_embargoed: true, storage_class: :hdd).map(&:datacenter).uniq
    end

    # HACK:  When restoring/migrating a database from GHES <3.2, we may be
    # running this new code with an old database schema.
    def self.have_cache_location_column?
      return true if !GitHub.enterprise?

      if defined?(@@have_cache_location_column)
        return @@have_cache_location_column
      end

      sql = GitHub::DGit::DB::FS::SQL.new <<-SQL
        SELECT 1 FROM information_schema.COLUMNS WHERE table_schema=DATABASE() AND table_name='fileservers' AND column_name='cache_location'
      SQL

      @@have_cache_location_column = sql.results.size > 0
      @@have_cache_location_column
    end
  end
end
