# typed: true
# frozen_string_literal: true

require "socket"
require "github/dgit/maintenance"
require "github/dgit/routing"
require "github/dgit/route"

module GitHub
  class DGit
    # GitRPC's dgit: protocol needs to interact with MySQL tables, to look
    # up routes and to update checksums.  But GitRPC isn't in a part of the
    # namespace that knows about MySQL.  So we hand it an instance of this
    # DGit::Delegate class to do the dirty work.  There's likely to be one
    # instance of DGit::Delegate for each GitRPC::Protocol::DGit object,
    # because DGit::Delegate, as implemented here, has the routes
    # pre-determined.
    #  - id:           repository or gist database ID, according to namespace,
    #                  used for database queries
    #  - shard_path:   shard path for the given repository or gist
    #  - routes:       optional list of GitHub::DGit::Delegate::Repository
    #                  instances to use as the routes
    class Delegate
      extend T::Helpers

      include GitHub::IFlipperActor
      include GitHub::VexiActor

      abstract!

      sig { abstract.returns(T.nilable(String)) }
      def _read_checksum_from_db; end

      sig { abstract.returns(Integer) }
      def repo_type; end

      sig { abstract.returns(String) }
      def namespace; end

      sig { abstract.returns(T::Array[GitHub::DGit::Replica]) }
      def dgit_replicas; end

      include Scientist

      UPDATE_BATCH_SIZE = 100

      attr_reader :id, :shard_path

      def initialize(id, shard_path, routes: nil)
        @id, @shard_path = id, shard_path
        if ::GitRPC.optimize_local_access
          @routes = @all_routes = @write_routes = @threepc_routes = optimize_local_access(routes)
        else
          @routes = @all_routes = @write_routes = @threepc_routes = routes
        end
      end

      # Part of the cache key for references.
      #
      # This is the spokes checksum. It should be fresh every time this
      # method gets called.
      def repository_reference_key
        if GitHub.spokesd_enabled?
          # Some subclasses aren't checksummed and don't have a
          # spokes_api object.  Return nil for them.
          # _read_checksum_from_db does the same.
          if @spokes_api
            @spokes_api.get_cache_key
          else
            nil
          end
        else
          _read_checksum_from_db
        end
      end

      # Read the checksum from the master replica.
      #
      # Use this when having the exact current checksum (or as close as
      # possible) is necessary.
      def read_checksum_from_db
        ActiveRecord::Base.connected_to(role: :writing) { _read_checksum_from_db }
      end

      # Look up routes for reading.  Or, more accurately, fetch the
      # already-pre-determined routes.
      #
      # Returns an array of GitRPC::Protocol::DGit::Route objects, sorted by
      # read_affinity.  A read should be directed to the first route in
      # the array.  Additional routes are provided so callers can
      # implement failover.  Callers do not need to implement load
      # balancing; any needed load balancing will be reflected in the
      # order of the returned array.
      def get_read_routes
        @routes ||= dgit_routes!(:read)
        ret = filter_routes(@routes)
        ret.empty? ? @routes : ret
      end

      def filter_routes(routes)
        if flipper_enabled?(:spokesd_filter_routes)
          new_filter_routes(routes)
        else
          science "filter_routes" do |e|
            e.run_if { GitHub.spokesd_enabled? }
            e.use { old_filter_routes(routes) }
            e.try { new_filter_routes(routes) }
          end
        end
      end

      def old_filter_routes(routes)
        routes.select do |route|
          !GitHub::DGit.is_route_offline?(route.original_host) &&
          !GitHub::DGit.is_overloaded?(route.original_host)
        end
      end

      def new_filter_routes(routes)
        routes.select do |route|
          !route.unreachable? && !route.overloaded?
        end
      end

      def filter_write_routes(routes)
        if flipper_enabled?(:spokesd_filter_write_routes)
          new_filter_write_routes(routes)
        else
          science "filter_write_routes" do |e|
            e.run_if { GitHub.spokesd_enabled? }
            e.use { old_filter_write_routes(routes) }
            e.try { new_filter_write_routes(routes) }
          end
        end
      end

      def old_filter_write_routes(routes)
        routes.select do |route|
          !GitHub::DGit.is_route_offline?(route.original_host)
        end
      end

      def new_filter_write_routes(routes)
        routes.select do |route|
          !route.unreachable?
        end
      end

      # Like #get_read_routes, but also include unhealthy (non-ACTIVE or bad-checksum) hosts.
      # *Will NOT return offline/overloaded hosts unless live_only=false.
      def get_all_routes(live_only: true)
        @all_routes ||= dgit_routes!(:all)
        return @all_routes unless live_only
        ret = filter_routes(@all_routes)
        ret.empty? ? @all_routes : ret
      end

      # Look up routes for writing.  Or, more accurately, fetch the
      # already-pre-determined routes.
      #
      # Returns an array of GitRPC::Protocol::DGit::Route objects, sorted
      # deterministically as per Route#<=>. Writes must be directed to all
      # routes in the array.
      #
      # Includes both healthy and unhealthy (checksum-out-of-sync) replicas, so
      # that we write newly pushed objects to unhealthy replicas. This lets us
      # repair them faster.
      #
      # The routes are ordered to ensure that healthy replicas come first. This
      # matters because babeld uses the first connectable replica for ref
      # discovery, so we want to ensure it's seeing an up-to-date view of ref
      # state.
      def get_write_routes
        get_writable_routes(:write)
      end

      # Look up routes for typical 3PC operations.  Or, more accurately, fetch
      # the already-pre-determined routes.  Note that some 3PC operations use
      # get_all_routes instead.
      #
      # Returns an array of GitRPC::Protocol::DGit::Route objects, sorted
      # deterministically as per Route#<=> to avoid dining philosophers
      # deadlocks in 3PC. 3PC operations must be directed to all routes in the
      # array.
      def get_3pc_routes
        get_writable_routes(:threepc)
      end

      # Check whether all replicas are healthy or not.
      def replicas_healthy?
        replicas = healthy_replicas(:all)
        # Check if the number of all (online) replicas matches the
        # number of replicas that are considered healthy.
        replicas.count(&:healthy?) == replicas.length
      end

      # Return the number of replicas that have to agree for write operations.
      def write_quorum
        # The quorom is calculated based on *all* replicas, including
        # offline ones. That is required to avoid a potential split-brain
        # situation.
        GitHub.dgit_quorum(get_all_routes(live_only: false).count(&:voting?))
      end

      # Return the number of replicas that have to agree for write operations
      # that require unanimous consensus.
      def unanimous_quorum
        @write_routes ||= dgit_routes!(:write)
        @write_routes.count(&:voting?)
      end

      def check_twirp_resp(resp)
        if !resp.error.nil?
          case resp.error.code
          when :not_found
            raise UnroutedError, resp.error.msg
          when :deadline_exceeded
            raise GitRPC::Timeout, resp.error.msg
          end
        end
        resp
      end

      def legacy_gitrpc_reader(timeout, options, function, args, kwargs, topology_context)
        check_twirp_resp(get_spokesd_client.legacy_gitrpc_reader(repo_type, id, timeout, options, function, args, kwargs, topology_context))
      end

      def async_legacy_gitrpc_reader(timeout, options, function, args, kwargs, topology_context)
        get_spokesd_client.async_legacy_gitrpc_reader(repo_type, id, timeout, options, function, args, kwargs, topology_context)
      end

      def legacy_gitrpc_writer(timeout, options, function, args, kwargs)
        check_twirp_resp(get_spokesd_client.legacy_gitrpc_writer(repo_type, id, timeout, options, function, args, kwargs))
      end

      def async_legacy_gitrpc_writer(timeout, options, function, args, kwargs)
        get_spokesd_client.async_legacy_gitrpc_writer(repo_type, id, timeout, options, function, args, kwargs)
      end

      def is_error(response)
        # The type of errors "detected" here happen at the communication layer:
        # 1. Spokesd having problems to talk to the fileservers
        # 2. Gitrpcd having problems while trying to talk to the actual unicorn
        ::GitHub::Spokes::Proto::LegacyGitrpc::V1::StatusCode::STATUS_CODE_OK != ::GitHub::Spokes::Proto::LegacyGitrpc::V1::StatusCode.const_get(response.ernicorn_response.status.code)
      end

      # Maps the routes passed as the argument to a topology context which can be used
      # as an argument in our legacy proxy read requests implementation
      def map_routes(routes = [])
        get_spokesd_client.build_topology_context(routes)
      end

      # Update checksums for a repo and its replicas as a write
      # operation proceeds.  It's legal to call this function several times.
      # Parameters:
      #  - network_id: network ID for the repository whose checksums are being updated.
      #  - repo_id: identifies the repository whose checksums are being updated.
      #  - replica_checksums: a hash of host => checksum for each host checksum
      #    that should be updated.  The host is associated with one of the
      #    routes returned by #get_write_routes, and the checksum is a SHA1 in
      #    version-prefixed hex40 form.  This parameter may be nil if no rows
      #    in `repository_replicas` need to be updated.
      #  - repo_checksum: a string with a SHA1 in version-prefixed hex40 form.
      #    This value is put in the `repositories` table as the desired checksum
      #    for all replicas of the repo.  This parameter may be nil if
      #    the master checksum doesn't need to be updated.
      def self.update_checksums(network_id, repo_id, is_wiki, replica_checksums, repo_checksum)
        db = GitHub::DGit::DB.for_network_id(network_id)
        repo_type = is_wiki ? GitHub::DGit::RepoType::WIKI : GitHub::DGit::RepoType::REPO
        ActiveRecord::Base.connected_to(role: :writing) do
          db.transaction do
            if replica_checksums && !replica_checksums.empty?
              sql = db.SQL.new network_id: network_id

              add_checksum = proc do
                if replica_checksums.values.uniq.size == 1
                  sql.add ":sum", sum: replica_checksums.values.first
                else
                  sql.add "CASE host"
                  replica_checksums.each do |host, checksum|
                    sql.add "WHEN :host THEN :sum", host: host, sum: checksum
                  end
                  sql.add "END"
                end
              end

              sql.add "UPDATE repository_replicas SET updated_at=NOW(), checksum ="
              add_checksum.call
              hosts = replica_checksums.keys
              sql.add "WHERE repository_id=:repo_id AND repository_type=:repository_type AND host IN :hosts AND checksum != ",
                repo_id: repo_id, hosts: hosts, repository_type: repo_type
              add_checksum.call
              sql.run
            end

            if repo_checksum
              sql = db.SQL.new <<-SQL, network_id: network_id, checksum: repo_checksum, repo_id: repo_id, repository_type: repo_type
                UPDATE repository_checksums
                  SET checksum=:checksum, updated_at=NOW()
                  WHERE repository_id=:repo_id AND repository_type=:repository_type AND checksum!=:checksum
              SQL
              sql.run
            end
          end # transaction
        end # connected_to
      end

      # Update checksums for multiple repositories on a single host in a
      # single `UPDATE` query.
      # Parameters:
      #  - network_id: network ID corresponding to the given repositories
      #  - host: the host to update the checksums on; one of the routes
      #    returned by #get_write_routes.
      #  - repo_type: the type of the repo to be updated
      #  - replica_checksums: a hash of repo_id => checksum that
      #    should be updated.  The key is a tuple of repo_id and repo_type,
      #    the checksum is a SHA1 in version-prefixed hex40 form.
      def self.update_checksums_for_host(network_id, host, repo_type, replica_checksums)
        fail if replica_checksums.size > UPDATE_BATCH_SIZE

        db = GitHub::DGit::DB.for_network_id(network_id)
        checksums_rows = ActiveRecord::Base.connected_to(role: :reading) do
          db.SQL.results(<<-SQL, network_id: network_id, repo_ids: replica_checksums.keys, host: host, repo_type: repo_type)
            SELECT repository_id, checksum
              FROM repository_replicas
              WHERE repository_id IN :repo_ids
                AND repository_type = :repo_type
                AND host = :host
          SQL
        end

        checksums_now = Hash[checksums_rows.map { |repo_id, checksum| [repo_id, checksum] }]
        fail unless checksums_now.size == checksums_rows.size

        repos_to_change = replica_checksums.select { |repo_id, newsum| checksums_now[repo_id] != newsum }
        return if repos_to_change.empty?

        ActiveRecord::Base.connected_to(role: :writing) do
          sql = db.SQL.new network_id: network_id
          sql.add "UPDATE repository_replicas SET updated_at = NOW(), checksum ="
          if repos_to_change.size == 1
            sql.add ":sum", sum: repos_to_change.first[1]
          else
            sql.add "CASE"
            repos_to_change.each do |repo_id, checksum|
              sql.add "WHEN repository_id = :repo_id THEN :sum", repo_id: repo_id, sum: checksum
            end
            sql.add "END"
          end
          sql.add "WHERE repository_id IN :repo_ids AND repository_type = :repo_type AND host = :host",
            repo_ids: repos_to_change.keys, repo_type: repo_type, host: host
          sql.run
        end
      end

      def self.update_gist_checksums(gist_id, replica_checksums, repo_checksum, host_to_activate: nil)
        ActiveRecord::Base.connected_to(role: :writing) do
          gist_db = GitHub::DGit::DB.for_gist_id(gist_id)
          gist_db.transaction do
            if replica_checksums && !replica_checksums.empty?
              sql = gist_db.SQL.new gist_id: gist_id

              add_checksum = proc do
                if replica_checksums.values.uniq.size == 1
                  sql.add ":sum", sum: replica_checksums.values.first
                else
                  sql.add "CASE host"
                  replica_checksums.each do |host, checksum|
                    sql.add "WHEN :host THEN :sum", host: host, sum: checksum
                  end
                  sql.add "END"
                end
              end

              sql.add "UPDATE gist_replicas SET updated_at = NOW(), checksum ="
              add_checksum.call
              hosts = replica_checksums.keys
              sql.add "WHERE gist_id = :gist_id AND host IN :hosts AND checksum != ", hosts: hosts
              add_checksum.call
              sql.run

              if host_to_activate && [repo_checksum, "ok"].include?(replica_checksums[host_to_activate])
                gist_db.SQL.run(<<-SQL, active: GitHub::DGit::ACTIVE, gist_id: gist_id, host: host_to_activate)
                  UPDATE gist_replicas
                    SET updated_at = NOW(), state = :active
                    WHERE gist_id = :gist_id AND host = :host
                SQL
              end
            end

            if repo_checksum
              gist_db.SQL.run(<<-SQL, checksum: repo_checksum, gist_id: gist_id, repository_type: GitHub::DGit::RepoType::GIST)
                UPDATE repository_checksums
                  SET checksum=:checksum, updated_at=NOW()
                  WHERE repository_id=:gist_id AND repository_type=:repository_type AND checksum!=:checksum
              SQL
            end
          end # transaction
        end # connected_to
      end

      def self.checksum_for_repo(network_id, repo_id, is_wiki)
        db = GitHub::DGit::DB.for_network_id(network_id)
        repo_type = is_wiki ? GitHub::DGit::RepoType::WIKI : GitHub::DGit::RepoType::REPO
        db.connection.uncached do
          sql = db.SQL.new \
            network_id: network_id,
            repo_id: repo_id,
            repository_type: repo_type
          sql.add <<-SQL
            SELECT checksum
              FROM repository_checksums
              WHERE repository_id=:repo_id AND repository_type=:repository_type
          SQL
          r = sql.results.first
          r && r.first
        end
      end

      def self.checksum_for_gist(gist_id)
        db = GitHub::DGit::DB.for_gist_id(gist_id)
        db.connection.uncached do
          sql = db.SQL.new \
            gist_id: gist_id,
            repository_type: GitHub::DGit::RepoType::GIST
          sql.add <<-SQL
            SELECT checksum
              FROM repository_checksums
              WHERE repository_id=:gist_id AND repository_type=:repository_type
          SQL
          r = sql.results.first
          r && r.first
        end
      end

      # Called for all route/node related failures that GitRPC chooses to
      # suppress.  In particular, any time a replica fails while another one
      # succeeds, GitRPC will return the successful answer and call
      # `on_route_error` for the failure(s).  Also, any time a GitRPC read call
      # is unable to connect to one or more backends, those connection failures
      # will be reported here.
      #
      # The purpose of this function is to mark the failing node as
      # misbehaving.  In the case of writes, 3PC or recompute_checksums
      # will advance all well-behaved nodes and leave the failed node for
      # repair.  In the case of reads, the node is simply not contacted
      # for a while.
      #
      # In any event, the exception goes to Failbot and graphite so it
      # doesn't get masked completely.
      def on_route_error(route, error)
        host = route.original_host
        GitHub::DGit.set_route_offline(host)
        GitHub.stats.increment "dgit.#{host}.rpc-error" if GitHub.enterprise?
        GitHub.dogstats.increment("dgit.rpc-error", tags: ["server:#{host}", "server_datacenter:#{route.datacenter}", "route_offline:true"])
        GitHub.logger.error({ :exception => error, "gh.dgit.delegate.flipper_id" => "#{namespace}##{@id}", "gh.spokes.fileserver" => host, "gh.dgit.should_set_route_offline" => true })
      end

      # Called for all app/command related failures that GitRPC chooses to
      # suppress.
      def on_app_error(route, error)
        host = route.original_host
        GitHub.stats.increment "dgit.#{host}.rpc-error" if GitHub.enterprise?
        GitHub.dogstats.increment("dgit.rpc-error", tags: ["server:#{host}", "server_datacenter:#{route.datacenter}", "route_offline:false"])
        GitHub.logger.error({ :exception => error, "gh.dgit.delegate.flipper_id" => "#{namespace}##{@id}", "gh.spokes.fileserver" => host, "gh.dgit.should_set_route_offline" => false })
      end

      def flipper_id
        case namespace
        when "repository"
          "Repository:#{id}"
        when "network"
          "RepositoryNetwork:#{id}"
        when "gist", "gist-creation"
          "Gist:#{id}"
        when "wiki"
          "Wiki:#{id}"
        else
          nil
        end
      end

      def vexi_id
        flipper_id
      end

      # Helper to make the feature flag state available in GitRPC
      def flipper_enabled?(flipper_key)
        GitHub.respond_to?(:flipper) && GitHub.flipper[flipper_key].enabled?(self)
      end

      def proxy_gitrpc_through_spokesd?
        if !use_fakerpc? && GitHub.spokesd_enabled?
          if namespace == "repository" && flipper_enabled?(:proxy_gitrpc_through_spokesd)
            return true
          elsif namespace == "wiki" && flipper_enabled?(:proxy_gitrpc_for_wikis)
            return true
          end
        end
        false
      end

      def proxy_gitrpc_send_demux?
        if !use_fakerpc? && GitHub.spokesd_enabled?
          if namespace == "repository" && flipper_enabled?(:proxy_gitrpc_send_demux)
            return true
          end
        end
        false
      end

      # Called to report a warning.  GitRPC doesn't have direct access to
      # splunk or Failbot.
      def on_warning(error)
        GitHub.logger.error({ :exception => error, "gh.dgit.delegate.flipper_id" => "#{namespace}##{@id}" })
      end

      # Called to record or resolve disagreements. Log first, then
      # the default implementation should recompute checksums;
      # if answers disagree, then replicas may well have diverged.
      #
      # This method is overridden by derived classes
      def on_disagreement(answers, errors)
        GitHub.logger.info("disagreement during 3pc",
                           "gh.dgit.delegate.flipper_id" => "#{namespace}##{@id}",
                           "gh.dgit.gitrpc.answers" => answers,
                           "gh.dgit.gitrpc.errors" => errors)
      end

      # Make GitRPC::Protocol::DGit use same-machine, fakerpc backends for
      # unit tests and replicate-repo.
      def use_fakerpc?
        Rails.env.test? || !!($0 =~ /replicate-repo/)
      end

      private

      # Look up routes for writing.  Or, more accurately, fetch the
      # already-pre-determined routes.  This function underlies
      # get_write_routes and get_3pc_routes.
      #
      # Returns an array of GitRPC::Protocol::DGit::Route objects,
      # sorted deterministically as per Route#<=> to avoid dining
      # philosophers deadlocks in 3PC. Writes must be directed to all
      # routes in the array.
      #
      # Parameters:
      #  - type: the type of route (:write or :threepc) to fetch.
      def get_writable_routes(type)
        if type == :write
          @write_routes ||= dgit_routes!(type)
          routes = @write_routes
        else
          @threepc_routes ||= dgit_routes!(type)
          routes = @threepc_routes
        end

        # Filter for only believed-to-be-online hosts, unless that would
        # put us below a quorum.  Specifically, if one host is failed
        # (especially if its disk is hung), we'd rather skip the write to
        # it completely than hang for 1, 5, or 9 seconds trying to contact
        # it.
        ret = filter_write_routes(routes)

        voters = ret.count(&:voting?)
        if voters < write_quorum
          ret = routes
          voters = ret.count(&:voting?)
        end

        if voters < write_quorum
          msg = "#{voters} voting"
          non_voters = ret.length - voters
          msg << " (and #{non_voters} non-voting)" if non_voters > 0
          msg << " replicas available; #{write_quorum} required"
          raise InsufficientQuorumError, msg
        end

        ret.sort
      end

      # optimize_local_access sorts the replica list to ensure a local replica will be chosen first if it's available.
      def optimize_local_access(replicas)
        return replicas if replicas.nil?
        idx = replicas.index { |replica| ::GitRPC.local_access? replica.host }
        return replicas if idx.nil?
        local = replicas.delete_at(idx)
        replicas.unshift(local)
      end

      def running_on_cache_server?
        !!ENV["ENTERPRISE_CLUSTER_CACHE_LOCATION"]
      end

      def this_cache_location
        ENV["ENTERPRISE_CLUSTER_CACHE_LOCATION"]
      end

      def healthy_replicas(type)
        @replicas ||= dgit_replicas
        @replicas = optimize_local_access(@replicas) if ::GitRPC.optimize_local_access
        Failbot.push delegate_replicas: @replicas.map(&:host).inspect

        # If we don't have any replicas or any checksum, this repository is
        # totally unknown to us. This should be a distinct condition from having
        # an insufficient number of healthy replicas.
        if @replicas.empty? && read_checksum_from_db.nil?
          raise NotFoundError, "#{namespace}/#{@id} unknown to spokes"
        end

        healthy = if type == :all
          @replicas.select { |r| r.online? && !r.dormant? }
        elsif type == :write
          # This intentionally excludes dormant and failed replicas.
          if GitHub.write_only_to_healthy_replicas
            @replicas.select { |r| r.healthy? && !r.cache_replica? }
          else
            @replicas.select { |r| r.online? && r.active? && !r.cache_replica? }
          end
        elsif type == :threepc
          @replicas.select { |r| r.healthy? && !r.cache_replica? }
        else
          if running_on_cache_server?
            cache_replicas = @replicas.select { |r| r.healthy_cache? && r.in_cache_location?(this_cache_location) }
            non_cache_replicas = @replicas.select { |r| r.healthy? && !r.cache_replica? }
            cache_replicas + non_cache_replicas
          else
            @replicas.select { |r| r.healthy? && !r.cache_replica? }
          end
        end

        if healthy.size < @replicas.size
          Failbot.push delegate_healthy_hosts: healthy.map(&:host).inspect
        end

        # Deal with fileservers.empty? now, but defer checking if
        # fileservers.length < quorum until we know if the rpc op is a
        # read or a write.
        raise UnroutedError, explain_failure(@replicas) if healthy.empty?

        healthy
      end

      # This default implementation is used for everything except
      # GistCreation:
      def dgit_routes!(type)
        replicas = healthy_replicas(type)

        # Make gitrpc routes for the @replicas.
        replicas.map { |replica| replica.to_route(@shard_path) }
      end

      def explain_failure(replicas)
        csum = replicas.empty? ? "" : replicas.first.expected_checksum
        csum ||= ""

        "no available servers for #{namespace}##{@id}: [#{csum[0..6]}], " +
          replicas.map do |rep|
            %Q{[#{rep.host},#{GitHub::DGit::STATES[rep.state][0]},#{rep.checksum[0..6]},#{rep.online? ? "on" : "off"}]}
          end.join(", ")
      end

      def get_spokesd_client
        @@spokesd_client ||= GitHub::Spokes::Client::Spokesd.instance
      end

      class Repository < Delegate
        attr_reader :network_id

        def initialize(network_id, id, shard_path, routes: nil)
          @network_id = network_id
          @spokes_api = SpokesAPI::Client.for_repository(id, network_id: network_id)
          super(id, shard_path, routes: routes)
        end

        def namespace
          "repository"
        end

        # Read the repository checksum from the DB. For the answer to be
        # reliable, this method must be called while holding the
        # dgit-state lock and the caller must call this on the master
        # mysql replica.
        def _read_checksum_from_db
          Delegate.checksum_for_repo(@network_id, @id, false)
        end

        def write_checksums_to_db(replica_checksums, repo_checksum)
          GitHub::DGit::threepc_debug "update_checksums #{namespace}: (nw_id: #{@network_id}) #{@id}, " \
                                      "#{replica_checksums.inspect} " \
                                      "#{repo_checksum.inspect}"

          Delegate.update_checksums(@network_id, @id, false, replica_checksums, repo_checksum)
        end

        def on_disagreement(answers, errors)
          super
          SpokesRecomputeChecksumsJob.perform_later(@id, false)
        end

        def repo_type
          GitHub::DGit::RepoType::REPO
        end

        private

        def dgit_replicas
          GitHub::Spokes.client.all_replicas(@network_id, @id, GitHub::DGit::RepoType::REPO)
        end
      end

      class Wiki < Delegate
        attr_reader :network_id

        def initialize(network_id, id, shard_path)
          @network_id = network_id
          @spokes_api = SpokesAPI::Client.for_wiki(id, network_id: network_id)
          super(id, shard_path)
        end

        def namespace
          "wiki"
        end

        # Read the wiki's checksum from the DB. For the answer to be
        # reliable, this method must be called while holding the
        # dgit-state lock and the caller must call this on the master
        # mysql replica.
        def _read_checksum_from_db
          Delegate.checksum_for_repo(@network_id, @id, true)
        end

        def write_checksums_to_db(replica_checksums, repo_checksum)
          GitHub::DGit::threepc_debug "update_checksums #{namespace}: (nw_id: #{@network_id}) #{@id}, " \
                                      "#{replica_checksums.inspect} " \
                                      "#{repo_checksum.inspect}"

          Delegate.update_checksums(@network_id, @id, true, replica_checksums, repo_checksum)
        end

        def on_disagreement(answers, errors)
          super
          SpokesRecomputeChecksumsJob.perform_later(@id, true)
        end

        def repo_type
          GitHub::DGit::RepoType::WIKI
        end

        private

        def dgit_replicas
          GitHub::Spokes.client.all_replicas(@network_id, @id, GitHub::DGit::RepoType::WIKI)
        end
      end

      class Gist < Delegate
        attr_reader :name

        def initialize(id, name, shard_path)
          super(id, shard_path)
          @name = name
          @spokes_api = SpokesAPI::Client.for_gist(id, gist_name: name)
        end

        def namespace
          "gist"
        end

        # Read the gist's checksum from the DB. For the answer to be
        # reliable, this method must be called while holding the
        # dgit-state lock and the caller must call this on the master
        # mysql replica.
        def _read_checksum_from_db
          Delegate.checksum_for_gist(@id)
        end

        def write_checksums_to_db(replica_checksums, repo_checksum)
          GitHub::DGit::threepc_debug "update_checksums #{namespace}: #{@id}, " \
                                      "#{replica_checksums.inspect} " \
                                      "#{repo_checksum.inspect}"

          Delegate.update_gist_checksums(@id, replica_checksums, repo_checksum)
        end

        def on_disagreement(answers, errors)
          super
          SpokesRecomputeGistChecksumsJob.perform_later(@id)
        end

        def repo_type
          GitHub::DGit::RepoType::GIST
        end

        private

        def dgit_replicas
          GitHub::Spokes.client.all_replicas(nil, @id, GitHub::DGit::RepoType::GIST)
        end
      end

      class GistCreation < Delegate
        def initialize(name, shard_path, fileservers)
          routes = fileservers.map { |fileserver| fileserver.to_route(shard_path) }

          super(nil, shard_path, routes: routes)
          @name = name
        end

        def dgit_replicas; end

        def namespace
          "gist-creation"
        end

        def _read_checksum_from_db
          # During gist creation, there is no pre-checksum
          nil
        end

        def write_checksums_to_db(replica_checksums, repo_checksum)
          # During gist creation, we don't write the checksums to the DB:
        end

        def on_disagreement(answers, errors)
          # Report disagreements during creation: can't enqueue a recompute
          # checksums job at this stage because there is no such gist ID.
          GitHub.logger.info("disagreement on gist creation",
                             "gh.dgit.gitrpc.answers" => answers,
                             "gh.dgit.gitrpc.errors" => errors)
        end

        def repo_type
          GitHub::DGit::RepoType::GIST
        end

        def name
          @name
        end

        private

        def dgit_routes!(all_hosts)
          raise UnroutedError, "routes must be pre-defined"
        end
      end

      class Network < Delegate
        def initialize(id, shard_path)
          super(id, shard_path)
        end

        def namespace
          "network"
        end

        # Networks do not have checksums, but the parent class has methods
        # for accessing it.
        def _read_checksum_from_db
          nil
        end

        def repo_type
          GitHub::DGit::RepoType::NETWORK
        end

        private

        def dgit_replicas
          GitHub::Spokes.client.all_replicas(@id, nil, GitHub::DGit::RepoType::NETWORK)
        end

        def explain_failure(replicas)
          "no available servers for network##{@id}: " +
            replicas.map do |rep|
              %Q{[#{rep.host},#{GitHub::DGit::STATES[rep.state][0]},#{rep.online? ? "on" : "off"}]}
            end.join(", ")
        end
      end

      module Removal
        extend T::Helpers

        abstract!

        sig { abstract.params(live_only: T::Boolean).returns(T::Array[GitHub::DGit::Replica]) }
        def get_all_routes(live_only: false); end

        def on_disagreement(answers, errors)
          nil
        end

        def get_write_routes
          get_all_routes(live_only: false)
        end
      end

      class RepositoryRemoval < Repository
        include Removal
      end

      class WikiRemoval < Wiki
        include Removal
      end
    end
  end
end
