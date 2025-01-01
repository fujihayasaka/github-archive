# typed: false
# frozen_string_literal: true

# Queries to see which repo and network replicas need maintenance

require "github/config/mysql"
require "github/config/redis"
require "github/dgit/error"
require "github/dgit/repo_types"
require "github/dgit/states"
require "github/dgit/constants"
require "github/dgit/cold_storage_sql"
require "github/dgit/replication_strategy"
require "github/dgit/util"
require "github/slice_query"

require "set"

module GitHub
  class DGit
    class Maintenance
      include SliceQuery

      # schedule no more than this many jobs per host, per interval
      # this is the default; it can scale based on the value of
      # /etc/github/background-job-worker-count on a particular fileserver
      MAX_JOBS_PER_HOST = 100

      # keep no more than this many old pre-repair backups of any network
      MAX_REPAIR_BACKUPS = 4

      # only look for bad checksums in repository_checksums and
      # repository_replicas rows that have been updated this recently.
      BAD_CHECKSUMS_INTERVAL = 60  # minutes

      # The minimum age of a newly created replica (which includes entire
      # newly created or newly imported networks) before we're willing to
      # rebalance it to another host.
      # This is specifically to prevent races between creation-ish
      # processes (creating a repo, importing a repo, creating a replica)
      # and deleting a replica.
      MIN_REBALANCING_AGE = 60  # minutes

      # Number of times to attempt to rsync a backup
      # in preparation for a repo or gist repair.
      BACKUP_RSYNC_ATTEMPTS = 3

      # Cap replica counts at this number (generally 9) for the purposes
      # of graphing them.  That is, there will be `dgit.replica-counts.X`
      # metrics for all X in (0..REPLICA_GRAPH_MAX_COPIES).
      REPLICA_GRAPH_MAX_COPIES = GitHub.dgit_default_copies * 3
      REPLICA_GRAPH_KEYS = ((0..REPLICA_GRAPH_MAX_COPIES).to_a - [GitHub.dgit_default_copies]).freeze

      def self.network_query_limit
        (GitHub.kv.get(sweeper_size_key("networks")).value { 1000 } || 1000).to_i # rubocop:todo GitHub/DoNotUseGlobalKv
      end

      def self.set_network_sweeper_query_limit(limit)
        GitHub.kv.set(sweeper_size_key("networks"), limit.to_s) # rubocop:todo GitHub/DoNotUseGlobalKv
      end

      def self.gist_query_limit
        (GitHub.kv.get(sweeper_size_key("gists")).value { 1000 } || 1000).to_i # rubocop:todo GitHub/DoNotUseGlobalKv
      end

      def self.set_gist_sweeper_query_limit(limit)
        GitHub.kv.set(sweeper_size_key("gists"), limit.to_s) # rubocop:todo GitHub/DoNotUseGlobalKv
      end

      def self.sweeper_size_key(kind)
        "#{query_namespace}:sweeper:#{kind}"
      end

      # General namespace for adjustable queries
      def self.query_namespace
        "dgit"
      end

      # Annotation for automatically tracking timing stats for
      # the MySQL query methods.  For example, to track stats
      # in the "dgit.queries.get_the_foos.time" stat namespace:
      #
      #     def self.get_the_foos(a, b, c, ...)
      #       # wild MySQL queries go here like normal
      #     end
      #     track_query_time :get_the_foos
      #
      def self.track_query_time(query_method_name)
        singleton_class.class_eval do
          orig_method = "#{query_method_name}_untracked"
          alias_method orig_method, query_method_name
          stat_method_name = query_method_name.to_s.sub("?", "")
          define_method query_method_name do |*args|
            start = Time.now
            result = GitHub.dogstats.time("dgit.queries", tags: ["query:#{stat_method_name}"]) do
              if args.last.class == Hash
                kwargs = args.pop
                self.send(orig_method, *args, **kwargs)
              else
                self.send(orig_method, *args)
              end
            end
            GitHub.stats.timing("dgit.queries.#{stat_method_name}.time", Time.now - start) if GitHub.enterprise?
            result
          end
        end
      end

      # Create `count` replicas of a network or gist (depending on provided context)
      def self.create_replicas(id, count, old_replicas = nil, helper = FixVotingReplicaCounts.new(nil), ctx:)
        old_replicas ||= ctx.all_replicas(id)
        ok_replicas = old_replicas.select(&:healthy?)
        raise ReplicaCreateError, "No healthy source host: #{old_replicas.inspect}" if ok_replicas.empty?
        # We reject anything which is not healthy to avoid races. There is some
        # potential to optimize this so we only reject the close race of
        # DESTROYING.
        same_votingness_replicas = helper.filter_replicas(ok_replicas)
        evac_hosts = same_votingness_replicas.select(&:evacuating?).map(&:host)
        new_hosts = GitHub.dogstats.time("dgit.maintenance.pick_hosts",
                                         tags: ["maint:#{ctx.entity}"]) do
          helper.pick_hosts(count, old_replicas)
        end

        new_hosts.each do |host|
          if (evac = evac_hosts.shift)
            ctx.enqueue_move_replica(id, evac, host)
          else
            ctx.enqueue_create_replica(id, host)
          end
        end
      end

      # Queue a job to destroy one replica of a network.
      #   - network_id = the network whose replica to destroy
      #   - host       = which replica to destroy
      def self.destroy_network_replica(network_id, host, ctx: NetworkMaintenanceContext.new)
        ctx.enqueue_destroy_replica(network_id, host)
      end

      # Queue a job to repair one repository with checksum stuck at 'creating'.
      #   - repo_id         = the repo whose replica to repair
      #   - repo_type       = type of repo
      #   - host            = an arbitrarily chosen host to drive the repair
      def self.repair_doa_repo(repo_id, repo_type, host)
        is_wiki = (repo_type == GitHub::DGit::RepoType::WIKI)
        SpokesRepairDoaRepoJob.set(queue: "maint_#{host}").perform_later(repo_id, is_wiki)
      end

      # Queue a job to repair one replica of a network.  This will fix
      # all repos within the network.  This is somewhat more expensive,
      # but more comprehensive, than repairing just a single repo.  Do
      # this when a network is in the FAILED state, e.g. after an
      # unexpected 3pc error.
      #   - network_id = the network whose replica to repair
      #   - host       = which replica to repair
      def self.repair_network_replica(network_id, host)
        SpokesRepairNetworkReplicaJob.set(queue: "maint_#{host}").perform_later(network_id, host)
      end

      # Queue a job to repair one replica of a gist.  Do this when
      # a gist is in the FAILED state, e.g. after an unexpected 3pc
      # error.
      #   - gist_id = the gist whose replica to repair
      #   - host    = which replica to repair
      def self.repair_gist_replica(gist_id, host)
        SpokesRepairGistReplicaJob.set(queue: "maint_#{host}").perform_later(gist_id, host)
      end

      # Recompute the checksum on all replicas, and make sure there's
      # still a repair needed.  The repository's expected checksum is
      # updated to whatever checksum gets computed on the primary-reader
      # node.  We don't want to invalidate all routes.
      #
      # Returns a hash mapping { host => checksum }, plus a bonus
      # { :repo => repo_expected_checksum }
      #
      # recompute_checksums will run to completion with hosts unavailable,
      # as long as the designated read_host can compute the checksum.  The
      # returned hash will be missing keys for any host that was
      # unavailable.
      #
      # Note that this operation grabs the dgit lock on each node, but not
      # all at once like a 3PC writer.  It's possible that some other
      # update will sneak in between the updates, leaving replicas out of
      # sync.  The primary-reader will have the "right" checksum, and one
      # or both of the others may be out of sync.  Maintenance jobs will
      # clean that up, though in the worst case, we could roll back a push
      # we just told the user we accepted.
      def self.recompute_checksums(repo, read_host, is_wiki: false, force_dgit_init: false, vote_fallback: false)
        # If the repo already has some sort of checksums, use 3PC to
        # recompute them.  If it doesn't -- e.g., it has "creating" or
        # "bad" -- then 3PC won't work, and we have to use `dgit-state
        # init`.  Fortunately, if the checksum is "creating," there's no
        # possibility we'll race against a successful 3PC, so `dgit-state
        # init` is safe.
        if !force_dgit_init
          voting_strategy =
            if vote_fallback
              :vote_fallback
            elsif read_host == :vote
              :vote
            else
              :checksum_host
            end

          if is_wiki
            wc = GitHub::DGit::Routing.wiki_checksum(repo.network.id, repo.id)
            if wc =~ /\A\d+:[0-9a-f]{10,}\z/
              res = GitHub.dogstats.time("dgit.recompute_checksums", tags: ["type:wiki", "method:3pc"]) do
                repo.unsullied_wiki.recompute_checksums(voting_strategy, read_host, ignore_dissent: true) # XXX: See FIXME in Repository#recompute_checksums.
              end
              return log_unanimity(:wiki, res)
            end
          else
            rc = GitHub::DGit::Routing.repo_checksum(repo.network.id, repo.id)
            if rc =~ /\A\d+:[0-9a-f]{10,}\z/
              res = GitHub.dogstats.time("dgit.recompute_checksums", tags: ["type:repo", "method:3pc"]) do
                repo.recompute_checksums(voting_strategy, read_host, ignore_dissent: true) # XXX: See FIXME in Repository#recompute_checksums.
              end
              return log_unanimity(:repo, res)
            end
          end
        end

        ret = {}
        GitHub.dogstats.time("dgit.recompute_checksums", tags: ["type:#{is_wiki ? "wiki" : "repo"}", "method:rpc"]) do
          replicas = GitHub::DGit::Routing.all_repo_replicas(repo.id, is_wiki).select(&:online?).reject(&:dormant?).reject(&:destroying?)
          return {} if replicas.empty?

          # You might wonder, "Why look up the repository in the database?" Good question!
          # In RepositoryNetwork#new_extract, the dup'd repository's network_id gets changed
          # before the routes get changed in the database. This means that all_repo_replicas
          # loads the old routes, even though repo.original_shard_path includes the new
          # network ID. In other words, we'd end up looking for the new replicas on the
          # old fileservers. Previously, this code only operated on the union of the
          # (new) network's hosts and the (old) repository's hosts, and it used the old
          # network_id because of the way it created the GitRPC clients. So that all worked
          # out OK. Now that we're using repo.original_shard_path to find the repository on
          # disk, we need to have the same network ID that was used for the routes. This
          # new code assumes that the value of repo.network_id (in the database) matches
          # the network that the repository shares routes with. I think that's a valid
          # assumption.
          repo_for_shard_path = Repositories::Public.get_active_or_deleted!(repo.id)
          repo_for_shard_path = repo_for_shard_path.unsullied_wiki if is_wiki
          shard_path = repo_for_shard_path.original_shard_path

          replicas_by_url = Hash[replicas.map { |replica| [replica.to_route(shard_path).rpc_url, replica] }]
          answers, errors = ::GitRPC.send_multiple(replicas_by_url.keys, :dgit_state_init, [DGIT_CURRENT_CHECKSUM_VERSION], {})

          replicas_by_url.each do |url, replica|
            if checksum = answers[url]
              ret[replica.host] = checksum
              ret[:repo] = checksum if replica.host == read_host
            else
              e = errors[url]
              if e.is_a?(::GitRPC::DGitStateInitError) || e.is_a?(::GitRPC::InvalidRepository)
                orig_err = e
                e = ChecksumInitError.new("Could not dgit-state on #{replica.host}: #{orig_err}")
                # This replicates what we'd normally do inside the GitRPC client code
                backtrace = orig_err.backtrace || []
                backtrace += ["---- THE WIRE ----"] + caller
                e.set_backtrace(backtrace)
              end
              raise e if replica.host == read_host
              Failbot.report!(e, app: "github-dgit-debug", spec: repo.dgit_spec, checksums: ret, read_host: read_host)
            end
          end

          if read_host == :vote
            winner = GitHub::DGit::Util.get_majority(voter_checksums(ret))
            raise ChecksumInitError, "No clear majority; votes=#{ret.inspect}" unless winner
            ret[:repo] = winner
          end

          log_unanimity(is_wiki ? :wiki : :repo, ret)
        end
      ensure
        if ret
          replica_checksums = ret
            .reject { |k, _| k == :repo }
            .transform_values { |checksum| checksum == ret[:repo] ? "ok" : "bad" }

          GitHub::DGit::Delegate.update_checksums(repo.network.id, repo.id, is_wiki, replica_checksums, ret[:repo])
        end
      end

      # Filter a checksum-results hash to include voting hosts only
      #   hash: a Hash of { host => checksum, host => checksum }
      #   returns: a Hash with the same layout, but all keys correspond to
      #            voting hosts
      def self.voter_checksums(hash)
        voting_hosts = Set.new(GitHub::DGit.get_hosts(voting_only: true, storage_class: :all))
        hash.select { |k, _v| voting_hosts.include?(k) }
      end

      # Recompute checksums, and suppress any DGit exceptions
      def self.safely_recompute_checksums(repo, read_host, is_wiki: false)
        recompute_checksums(repo, read_host, is_wiki: is_wiki)
      rescue GitHub::DGit::Error => e
        raise if Rails.env.test?
        Failbot.report!(e, app: "github-dgit-debug", spec: repo.dgit_spec)
      end

      # Recompute the checksum on all replicas for the given gist.
      # See also `recompute_checksums`.
      def self.recompute_gist_checksums(gist, read_host, store_to_sql: true, fileservers: nil, host_to_activate: nil)
        ret = {}

        # Get all online hosts for the given gist regardless of checksum
        # on each host.
        #
        # We have to deal with a nil `gist.id` at creation time, when the
        # gist object hasn't been saved yet and has neither an ID nor a
        # row in the database.  `all_gist_replicas` depends on state in
        # the database, so when `gist.id` is nil, we use the unsaved state
        # to fetch the host list instead.
        GitHub.dogstats.time("dgit.recompute_checksums", tags: ["type:gist", "method:rpc"]) do
          replica_by_host = {}
          routes =
            if fileservers
              fileservers.map { |fs| fs.to_route(gist.original_shard_path) }
            elsif gist.id
              replicas = GitHub::DGit::Routing.all_gist_replicas(gist.id).select(&:online?).reject(&:dormant?).reject(&:destroying?)
              replicas.each { |rep| replica_by_host[rep.host] = rep }

              replicas.map { |rep| rep.to_route(gist.original_shard_path) }
            else
              gist.rpc.backend.delegate.get_write_routes
            end

          hosts_by_url = Hash[routes.map { |route| [route.rpc_url, route.original_host] }]
          answers, errors = ::GitRPC.send_multiple(hosts_by_url.keys, :dgit_state_init, [DGIT_CURRENT_CHECKSUM_VERSION], {})

          hosts_by_url.each do |url, host|
            if checksum = answers[url]
              ret[host] = checksum
              ret[:repo] = checksum if host == read_host
            else
              e = errors[url]
              if e.is_a?(::GitRPC::DGitStateInitError) || e.is_a?(::GitRPC::InvalidRepository)
                orig_err = e
                e = ChecksumInitError.new("Could not dgit-state on #{host}: #{e}")
                # This replicas what we'd normally do inside the GitRPC client code
                backtrace = orig_err.backtrace || []
                backtrace += ["---- THE WIRE ----"] + caller
                e.set_backtrace(backtrace)
              end
              if host == read_host
                if e.is_a?(ChecksumInitError) && DGit::Util.is_evacuating?(read_host)
                  read_host = :vote
                else
                  raise e
                end
              end
              # Some replica may be in a CREATING state due to a concurrent job
              # (e.g. there are evacuations happening). In that case it's not
              # interesting that such a replica failed to generate a checksum
              # and it can generate quite a bit of noise.
              if replica_by_host[host]&.state != GitHub::DGit::CREATING
                Failbot.report!(e, app: "github-dgit-debug", spec: gist.dgit_spec, checksums: ret, read_host: read_host)
              end
            end
          end

          if read_host == :vote
            winner = GitHub::DGit::Util.get_majority(voter_checksums(ret))
            raise ChecksumInitError, "No clear majority; votes=#{ret.inspect}" unless winner
            ret[:repo] = winner
          end

          log_unanimity(:gist, ret)
        end
      ensure
        if store_to_sql
          replica_checksums = ret
            .reject { |k, _| k == :repo }
            .transform_values { |checksum| checksum == ret[:repo] ? "ok" : "bad" }

          GitHub::DGit::Delegate.update_gist_checksums(gist.id,
                                                       replica_checksums,
                                                       ret[:repo],
                                                       host_to_activate: host_to_activate)
        end
      end

      def self.log_unanimity(type, checksums)
        raise "unknown checksum type #{type}" unless [:wiki, :repo, :gist].include? type
        uniq = checksums.values.uniq.size
        GitHub.dogstats.increment("dgit.recompute_checksums.uniq", tags: ["type:#{type}", "uniq:#{uniq}"])
        checksums
      end

      def self.init_gist_checksums(gist)
        recompute_gist_checksums(gist, :vote, store_to_sql: false)
      end

      # Change the state of a network_replica
      # network_id - the network ID of the replica to change
      # host - the hostname (e.g. github-dfs-1122334) of the replica to change
      # new_state - the new state of the replica (one of the scalar values in lib/github/dgit/states.rb)
      # prior_state - if provided, only change the state of the replica if the state in the database
      #               matches this prior state. This value may be an array, if prior_state is allowed
      #               to be one of several values.
      def self.set_network_state(network_id, host, new_state, prior_state = nil, update_time = true, ctx: NetworkMaintenanceContext.new)
        ctx.set_replica_state(network_id, host, new_state, prior_state, update_time)
      end

      def self.set_gist_state(gist_id, host, new_state, prior_state = nil, update_time = true, ctx: GistMaintenanceContext.new)
        ctx.set_replica_state(gist_id, host, new_state, prior_state, update_time)
      end

      def self.rebalance_read_weight(network_id, new_host: nil, replicas: nil, ctx: NetworkMaintenanceContext.new)
        ctx.rebalance_read_weight(network_id, new_host: new_host, replicas: replicas)
      end

      def self.rebalance_gist_read_weight(gist_id, replicas: nil, ctx: GistMaintenanceContext.new)
        ctx.rebalance_read_weight(gist_id, replicas: replicas)
      end

      # Delete the given gist's bits from disk for the given replica.
      #   - gist_id   - gist ID, used for logging
      #   - replica   - replica object for the given gist
      #   - path      - gist's original_shard_path
      def self.delete_gist_from_disk_on_replica(gist_id, replica, path)
        host = replica.host

        original_shard_path = path
        path = GitHub::DGit.dev_route(path, host) if Rails.env.development? || Rails.env.test?

        # the final 36 in this regex stems from Gist::random_sha -> SecureRandom.hex(16).
        v3_pattern = %r{\A#{GitHub.repository_root}/(?:dgit\d/)?[0-9a-f]/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{2}/gist/[0-9a-f]{32}.git\z}
        # the final 20 in this regex stems from Gist::random_sha -> SecureRandom.hex(10).
        v2_pattern = %r{\A#{GitHub.repository_root}/(?:dgit\d/)?[0-9a-f]/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{2}/gist/[0-9a-f]{20}.git\z}
        # before the SecureRandom scheme (v2), a decimal database ID number would be the final gist path component
        v1_pattern = %r{\A#{GitHub.repository_root}/(?:dgit\d/)?[0-9a-f]/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{2}/gist/[0-9]+.git\z}

        unless (path =~ v1_pattern) || (path =~ v2_pattern) || (path =~ v3_pattern)
          raise GitHub::DGit::ReplicaDestroyError, "Refusing to delete unexpected gist path #{path.inspect}"
        end

        cmd = ["rm", "-rf", path]  # woof

        begin
          GitHub.logger.info("start", "code.namespace" => "GitRPC", "code.function" => "fs_delete", "gh.spokes.storage_path" => path)
          if replica.online?
            rpc = replica.fileserver.build_maint_rpc(original_shard_path)
            rpc.fs_delete(path)
          end
        rescue ::GitRPC::InvalidRepository, ::GitRPC::ConnectionError, SocketError
          # Just a best effort
        end
      end

      # Back up a repository network or gist directory before beginning a repair.
      #   - rpc - an RPC handle for a given repository, network, or gist replica..
      #   - jobclass - the class of the caller
      def self.backup_before_repair_with_rpc(rpc, jobclass)
        src = rpc.backend.path
        parent = src.sub(%r{/\d+(?:\.wiki)?\.git/?$}, "").chomp("/")
        dest = "#{parent}.backup.#{Time.now.to_i}.#{jobclass.to_s.split('::').last}"
        excludes = %w[objects network.git/objects */audit_log audit_log]

        (1..BACKUP_RSYNC_ATTEMPTS).each do |backup_attempt|
          res = rpc.rsync("#{src}/", dest, archive: true, exclude: excludes)

          # Leave the loop if we succeeded
          break if res["ok"]

          # Fail silently if the directory is missing
          return if res["err"] =~ /no such file/i

          if backup_attempt == BACKUP_RSYNC_ATTEMPTS ||
              !GitHub::DGit::RETRYABLE_RSYNC_RESULTS.include?(res["status"])
            raise CommandError, "could not make a backup: #{res['err']}"
          end

          $stderr.puts "Backup attempt #{backup_attempt} of source #{src} failed with retryable result #{res['status']}"
        end

        rpc.prune_backups(parent, MAX_REPAIR_BACKUPS).each do |path, errstr|
          $stderr.puts "Could not delete backup #{path}: #{errstr}"
        end
      end

      # Insert placeholder network_replica rows into the database
      # for the given network ID and set of fileservers.
      def self.insert_placeholder_network_replicas(network_id, dgit_fileservers)
        allocator = GitHub::DGit::ReadWeightAllocator.new
        host_weights = allocator.choose_read_weights(allocator.new_replicas(dgit_fileservers))

        sql_now = GitHub::SQL::NOW
        nr_rows = []
        dgit_fileservers.each do |fs|
          nr_rows << [network_id, fs.name, GitHub::DGit::ACTIVE, host_weights.fetch(fs.name), sql_now, sql_now]
        end
        GitHub.logger.info("inserting placeholder network replicas",
                            "gh.repo.network_id" => network_id, "gh.sql.affected_rows_count" => nr_rows)

        # Retry to work around db issues https://github.com/github/database-infrastructure/issues/3613
        db = GitHub::DGit::DB.for_network_id(network_id)
        (1..3).each do
          begin
            delete_network_replicas_for_db(network_id, db)
            db.transaction do
              ActiveRecord::Base.connected_to(role: :writing) do
                db.SQL.run(<<-SQL, network_id: network_id, nr_rows: GitHub::SQL::ROWS(nr_rows))
                  INSERT INTO network_replicas
                    (network_id, host, state, read_weight, created_at, updated_at)
                  VALUES :nr_rows
                SQL
              end
            end
            break
          rescue ActiveRecord::ConnectionFailed => error
            GitHub.logger.info("encountered closed connection error while trying to insert network replicas",
                                "gh.repo.network_id" => network_id)
          end
        end
        GitHub.logger.info("finished inserting placeholder network replicas",
                            "gh.repo.network_id" => network_id)
      end

      # Insert placeholder repository_replica and repository_checksum rows into
      # the database for a given repository or wiki.
      #   - repo_type  - one of GitHub::DGit::RepoType::{REPO,WIKI}
      #   - repo_id    - repository ID for the repo or wiki
      #   - network_id - network ID for the repo or wiki, used to lookup hosts
      #                  by way of existing network_replica entries
      def self.insert_placeholder_replicas_and_checksums(repo_type, repo_id, network_id)
        sql_now = GitHub::SQL::NOW
        network_replica_hosts_and_ids = GitHub::DGit::Routing.all_network_replicas(network_id)
                                .map { |nr| [nr.fileserver.name, nr.db_network_replica_id] }

        rr_rows = []
        network_replica_hosts_and_ids.each do |nr_host, nr_id|
          rr_rows << [repo_id, repo_type, nr_id, nr_host, "creating", sql_now, sql_now]
        end
        GitHub.logger.info("inserting placeholder replicas", "gh.repo.id" => repo_id, "gh.repo.network_id" => network_id,
                           "gh.repo.type" => repo_type, "gh.sql.affected_rows_count" => rr_rows)
        checksum_row = [repo_id, repo_type, "creating", sql_now, sql_now]

        # Retry to work around db issues https://github.com/github/database-infrastructure/issues/3613
        db = GitHub::DGit::DB.for_network_id(network_id)
        (1..3).each do
          begin
            delete_repo_replicas_and_checksums_for_db(network_id, repo_id, [repo_type], db)
            ActiveRecord::Base.connected_to(role: :writing) do
              db.transaction do
                sql = db.SQL.new \
                               network_id: network_id,
                rr_rows: GitHub::SQL::ROWS(rr_rows)
                sql.add <<-SQL
                  INSERT INTO repository_replicas
                    (repository_id, repository_type, network_replica_id, host, checksum, created_at, updated_at)
                  VALUES :rr_rows
                SQL
                sql.run
                GitHub.logger.info("inserted repository replicas",
                                    "gh.sql.last_insert_id" => sql.last_insert_id,
                                    "gh.repo.id" => repo_id, "gh.repo.network_id" => network_id)

                sql = db.SQL.new \
                               network_id: network_id,
                checksum_row: checksum_row
                sql.add <<-SQL
                  INSERT INTO repository_checksums
                    (repository_id, repository_type, checksum, created_at, updated_at)
                  VALUES :checksum_row
                SQL
                sql.run
                GitHub.logger.info("inserted repository checksums",
                                    "gh.sql.last_insert_id" => sql.last_insert_id,
                                    "gh.repo.id" => repo_id, "gh.repo.network_id" => network_id)
              end # transaction
            end # connected_to
            break
          rescue ActiveRecord::ConnectionFailed => error
            GitHub.logger.error("failed to insert replicas, will retry",
                                  "gh.repo.id" => repo_id, "gh.repo.network_id" => network_id)
          end
        end
        GitHub.logger.info("finished insert_placeholder_replicas_and_checksums",
                            "gh.repo.id" => repo_id, "gh.repo.network_id" => network_id)
      end

      # Allocate weights for the given placeholder gist fileservers.
      def self.allocate_placeholder_gist_weights(gist_fileservers)
        allocator = GitHub::DGit::ReadWeightAllocator.new
        gist_host_weights = allocator.choose_read_weights(allocator.new_replicas(gist_fileservers))
      end

      # Insert placeholder gist_replica and repository_checksum rows into
      # the database for a given gist.  Used for fulfilling gist creation.
      # Read weights for the given fileservers are computed inline.
      #   - gist_id            - gist ID for the gist
      #   - gist_fileservers   - list of DGit::Fileserver objects for which to
      #                          insert placeholder gist_replica records
      #   - checksum           - optional initial checksum contents, defaults
      #                          to the value of "creating"
      def self.insert_placeholder_gist_replicas_and_checksums(gist_id, gist_fileservers, checksum = "creating")
        sql_now = GitHub::SQL::NOW
        state = GitHub::DGit::ACTIVE
        repo_type = GitHub::DGit::RepoType::GIST

        gist_hosts = gist_fileservers.map(&:name)
        gist_host_weights = allocate_placeholder_gist_weights(gist_fileservers)

        gr_rows = []
        gist_hosts.each do |host|
          gr_rows << [gist_id, host, checksum, state, gist_host_weights[host], sql_now, sql_now]
        end
        checksum_row = [gist_id, repo_type, checksum, sql_now, sql_now]

        ActiveRecord::Base.connected_to(role: :writing) do
          gist_db = GitHub::DGit::DB.for_gist_id(gist_id)
          gist_db.transaction do
            gist_db.SQL.run(<<-SQL, gist_id: gist_id, gr_rows: GitHub::SQL::ROWS(gr_rows))
              INSERT INTO gist_replicas
                (gist_id, host, checksum, state, read_weight, created_at, updated_at)
              VALUES :gr_rows
            SQL

            gist_db.SQL.run(<<-SQL, gist_id: gist_id, checksum_row: checksum_row)
              INSERT INTO repository_checksums
                (repository_id, repository_type, checksum, created_at, updated_at)
              VALUES :checksum_row
            SQL
          end # transaction
        end # connected_to
      end

      # Insert a single placeholder gist_replica and repository_checksum row
      # into the database for a given gist, for the purpose of a restore.
      #   - gist_id            - gist ID for the gist
      #   - gist_fileserver    - destination fileserver to where a gist backup
      #                          is being restored
      def self.insert_restore_placeholder_gist_replica_and_checksum(gist_id, gist_fileserver)
        insert_placeholder_gist_replicas_and_checksums(gist_id, [gist_fileserver], "restoring")
      end

      # remove a checksum row iff it is still creating or empty.
      # This allows callers to avoid races where we're about to recreate a dead-on-arrival
      # repository but another writer somehow completes a 3pc transaction.
      # Upon success, a DOA repo will have no checksum. If there is a checksum, it's not DOA.
      def self.reset_if_doa_repo(network_id, repo_id, is_wiki = false)
        repo_type = is_wiki ? GitHub::DGit::RepoType::WIKI : GitHub::DGit::RepoType::REPO

        ActiveRecord::Base.connected_to(role: :writing) do
          db = GitHub::DGit::DB.for_network_id(network_id)
          sql = db.SQL.new \
            network_id: network_id,
            repo_id: repo_id,
            repo_type: repo_type
          sql.add <<-SQL
            DELETE FROM repository_checksums
            WHERE repository_id = :repo_id
              AND repository_type = :repo_type
              AND (checksum = 'creating' OR checksum = '')
          SQL
          sql.run
        end
      end

      ####################################################################
      # Below here are internal routines.  They are public so tests and
      # scripts can get to them, but you're unlikely to need them.

      # The maximum time, in seconds, that a network replica can be in a
      # transient (creating, destroying, or repairing) state.
      MAX_TRANSIENT_TIME = 10800

      # Get all network replicas that have been in a transient state for
      # too long.  Caller decides what to do with them: e.g., destroy a
      # timed-out creation or repair, and restart a timed-out destroy.
      #
      # Return value is rows like [network_id, host, state].
      def self.get_network_replicas_for_cleanup(ctx: nil, only_network_id: nil, limit: nil)
        ctx ||= NetworkMaintenanceContext.new
        limit ||= network_query_limit
        bad_hosts = ctx.bad_hosts
        results = []
        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub::DGit::DB.each_network_db do |db|
            sql = db.SQL.new \
              limit: limit,
              states: [CREATING, DESTROYING, REPAIRING],
              max_transient_time: MAX_TRANSIENT_TIME
            sql.add <<-SQL
              SELECT network_id, host, state
                FROM network_replicas
                WHERE state IN :states
                  AND updated_at < NOW() - INTERVAL :max_transient_time SECOND
            SQL
            if only_network_id
              sql.add "AND network_id=:network_id", network_id: only_network_id
            elsif !bad_hosts.empty?
              sql.add "AND host NOT IN :bad_hosts", bad_hosts: bad_hosts
            end
            sql.add "LIMIT :limit", limit: limit
            results += sql.results
          end # each_network_db
        end # connected_to

        results
      end
      track_query_time :get_network_replicas_for_cleanup

      def self.get_gist_replicas_for_cleanup(only_gist_id: nil, limit: nil)
        ctx ||= GistMaintenanceContext.new
        limit ||= gist_query_limit
        bad_hosts = ctx.bad_hosts
        results = []

        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub::DGit::DB.each_gist_db do |db|
            sql = db.SQL.new \
              limit: limit,
              states: [CREATING, DESTROYING, REPAIRING, FAILED],
              max_transient_time: MAX_TRANSIENT_TIME
            sql.add <<-SQL
              SELECT gist_id, host, state
                FROM gist_replicas
                WHERE state IN :states
                  AND updated_at < NOW() - INTERVAL :max_transient_time SECOND
            SQL
            if only_gist_id
              sql.add "AND gist_id = :gist_id", gist_id: only_gist_id
            elsif !bad_hosts.empty?
              sql.add "AND host NOT IN :bad_hosts", bad_hosts: bad_hosts
            end
            sql.add "LIMIT :limit", limit: limit
            results += sql.results
          end # each_gist_db
        end # connected_to

        results
      end
      track_query_time :get_gist_replicas_for_cleanup

      def self.get_network_replicas_with_state(state, only_network_id: nil, limit: nil)
        limit ||= network_query_limit
        results = []

        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub::DGit::DB.each_network_db do |db|
            sql = db.SQL.new state: state
            sql.add <<-SQL
              SELECT network_id, host
                FROM network_replicas
                WHERE state=:state
            SQL
            sql.add "AND network_id=:network_id", network_id: only_network_id if only_network_id
            sql.add "LIMIT :limit", limit: limit
            results += sql.results
          end # each_network_db
        end # connected_to

        results
      end
      track_query_time :get_network_replicas_with_state

      def self.get_gist_replicas_with_state(state, only_gist_id: nil, limit: nil)
        limit ||= gist_query_limit
        results = []

        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub::DGit::DB.each_gist_db do |db|
            sql = db.SQL.new state: state
            sql.add <<-SQL
              SELECT gist_id, host
                FROM gist_replicas
                WHERE state=:state
            SQL
            sql.add "AND gist_id = :gist_id", gist_id: only_gist_id if only_gist_id
            sql.add "LIMIT :limit", limit: limit
            results += sql.results
          end # each_gist_db
        end # connected_to

        results
      end
      track_query_time :get_gist_replicas_with_state

      # Get all repo replicas that are active but have bad checksums.
      # Caller should initiate repairs.
      #
      # Note that while we check to make sure a replica is ACTIVE before
      # we try to repair it (because a network-level repair subsumes any
      # need for a repo-level repair), we don't actually care if the
      # relevant fileserver is marked `offline` in the `fileservers`
      # table.  If it's marked offline but actually online, repairs will
      # happen.  If it's actually offline, regardless of how it's marked,
      # repairs will get queued.
      #
      # Return value is rows like [repo_id, network_id, host, repository_type].
      #
      # TODO: prioritize by last-pushed time.
      def self.get_repo_replicas_with_bad_checksums(only_network_id: nil, limit: nil)
        limit ||= network_query_limit

        #
        # Recently-updated and now-mismatched tuples of the form:
        #
        #   [ repo_id, host, repository_type ]
        #
        # where the repository_replicas and repository_checksums
        # tables are each checked according to `updated_at`.
        #
        mismatches_found = ActiveRecord::Base.connected_to(role: :reading) do
          results = []
          updated_at_tables = GitHub.enterprise? || only_network_id ? [:ignored] : %w[rc rr]

          cache_servers = []
          if GitHub.enterprise?
            GitHub::DGit::DB.each_fileserver_db do |db|
              cache_servers |= db.SQL.results("SELECT host FROM fileservers WHERE cache_location IS NOT NULL").flatten
            end
          end

          GitHub::DGit::DB.each_network_db do |db|
            updated_at_tables.each do |updated_at_table|
              sql = db.SQL.new \
                limit: limit
              sql.add <<-SQL
                SELECT rr.repository_id,
                       rr.host,
                       rr.repository_type
                  FROM repository_replicas rr
                  JOIN repository_checksums rc
                    ON rr.repository_id = rc.repository_id
                   AND rr.repository_type = rc.repository_type
                   AND rr.checksum != rc.checksum
                   AND rr.checksum != "ok"
              SQL
              if only_network_id
                repository_ids = GitHub::DGit::Util.repo_ids_for(only_network_id)
                return [] if repository_ids.empty?
                sql.add "AND rr.repository_id IN :repository_ids", repository_ids: repository_ids
              end
              if updated_at_table != :ignored
                sql.add "AND :updated_at > NOW() - INTERVAL :recent MINUTE",
                  recent: BAD_CHECKSUMS_INTERVAL,
                  updated_at: GitHub::SQL.LITERAL("#{updated_at_table}.updated_at")
              end
              if !cache_servers.empty?
                sql.add "AND rr.host NOT IN :cache_servers", cache_servers: cache_servers
              end
              sql.add "LIMIT :limit"
              results |= sql.results
            end # updated_at_tables
          end # each_network_db
          results
        end # connected_to

        return [] if mismatches_found.empty?

        #
        # Lookup the network_id (source_id) for each of the
        # repository_id entries found in the above queries.
        #
        mismatch_repo_ids = mismatches_found.map(&:first)
        repo_id_to_network_id = repo_ids_to_network_ids(mismatch_repo_ids)

        network_ids = []
        if only_network_id
          network_ids = [only_network_id]
        else
          network_ids = repo_id_to_network_id.values.uniq
        end

        return [] if network_ids.empty?

        #
        # Map the set of network_ids to all active network_replicas.
        #
        network_id_and_host_set = ActiveRecord::Base.connected_to(role: :reading) do
          mapped_result = Set.new
          GitHub::DGit::DB.each_network_db do |db|
            sql = db.SQL.new \
              network_ids: network_ids,
              active: ACTIVE
            sql.add <<-SQL
              SELECT nr.network_id,
                     nr.host
                FROM network_replicas nr
               WHERE nr.network_id IN :network_ids
                 AND nr.state = :active
            SQL
            mapped_result |= sql.results
          end # each_network_db
          mapped_result
        end # connected_to

        #
        # Finally compute the end result list of
        #   [ repo_id, network_id, host, repository_type ]
        #
        result = []
        mismatches_found.each do |repo_id, host, repository_type|
          network_id = repo_id_to_network_id[repo_id]
          if network_id_and_host_set.include? [network_id, host]
            result << [repo_id, network_id, host, repository_type]
          end
        end

        if limit
          result.take(limit)
        else
          result
        end
      end
      track_query_time :get_repo_replicas_with_bad_checksums

      def self.get_gist_replicas_with_bad_checksums_in_interval(only_gist_id: nil, limit: nil, interval:)
        results = []

        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub::DGit::DB.each_gist_db do |db|
            %w[rc gr].map do |updated_at_table|
              sql = db.SQL.new \
                active: ACTIVE,
                repo_type: GitHub::DGit::RepoType::GIST
              sql.add <<-SQL
                SELECT gr.gist_id, gr.host FROM gist_replicas gr
                  JOIN repository_checksums rc ON gr.gist_id = rc.repository_id
                   AND rc.repository_type = :repo_type
                   AND rc.checksum != gr.checksum
                   AND gr.checksum != "ok"
              SQL
              if !GitHub.enterprise? && only_gist_id.nil?
                sql.add "AND :updated_at > NOW() - INTERVAL :recent MINUTE",
                  recent: interval,
                  updated_at: GitHub::SQL.LITERAL("#{updated_at_table}.updated_at")
              end
              sql.add "WHERE gr.state = :active"
              sql.add "AND gr.gist_id = :only_gist_id", only_gist_id: only_gist_id if only_gist_id
              sql.add "LIMIT :limit", limit: limit
              results |= sql.results
            end # "rc", "gr"
          end # each_gist_db
        end # connected_to

        results
      end

      def self.get_gist_replicas_with_bad_checksums(only_gist_id: nil, limit: nil)
        limit ||= gist_query_limit
        results = []

        # Try multiple times with smaller :updated_at intervals
        # each iteration in case the query is timing out.
        intervals = [BAD_CHECKSUMS_INTERVAL, BAD_CHECKSUMS_INTERVAL / 2, BAD_CHECKSUMS_INTERVAL / 4]
        intervals.each do |interval|
          begin
            results = get_gist_replicas_with_bad_checksums_in_interval(only_gist_id: only_gist_id, limit: limit, interval: interval)
            break
          rescue ActiveRecord::QueryCanceled, ActiveRecord::StatementTimeout => e
            results = []
            app_bucket = (interval == intervals.last) ? "github-dgit" : "github-dgit-debug"
            Failbot.report!(e, app: app_bucket)
          end # begin
        end # each interval

        results.take(limit)
      end
      track_query_time :get_gist_replicas_with_bad_checksums

      # Find hosts that are supposed to have replicas, but they're
      # trying to evacuate, or they don't exist
      # in the `fileservers` table at all.
      def self.get_bad_network_replica_hosts(ctx:)
        ActiveRecord::Base.connected_to(role: :reading) do
          result = []
          GitHub::DGit::DB.each_network_db do |db|
            sql = db.SQL.new <<-SQL
              SELECT sub.host
                FROM (
                  SELECT DISTINCT host FROM network_replicas
                ) sub
                LEFT JOIN fileservers fs ON sub.host = fs.host
                WHERE IFNULL(fs.evacuating, 1) != 0
            SQL
            if !ctx.voting.nil?
              sql.add("AND fs.non_voting = :voting", voting: !ctx.voting)
            end
            result += sql.results.flatten
          end # each_network_db
          result.uniq!
          tags = ["maint:network", "voting:#{ctx.voting_s}"]
          GitHub.dogstats.gauge("dgit.hosts_draining", result.size, tags: tags)
          result
        end # connected_to
      end
      track_query_time :get_bad_network_replica_hosts

      def self.get_bad_gist_replica_hosts(ctx:)
        ActiveRecord::Base.connected_to(role: :reading) do
          result = []
          GitHub::DGit::DB.each_gist_db do |db|
            sql = db.SQL.new <<-SQL
              SELECT sub.host
                FROM (
                  SELECT DISTINCT host FROM gist_replicas
                ) sub
                LEFT JOIN fileservers fs ON sub.host = fs.host
                WHERE IFNULL(fs.evacuating, 1) != 0
            SQL
            if !ctx.voting.nil?
              sql.add("AND fs.non_voting = :voting", voting: !ctx.voting)
            end
            result += sql.results.flatten
          end # each_gist_db
          result.uniq!
          tags = ["maint:gist", "voting:#{ctx.voting_s}"]
          GitHub.dogstats.gauge("dgit.hosts_draining", result.size, tags: tags)
          result
        end # connected_to
      end
      track_query_time :get_bad_gist_replica_hosts

      # Find mis-replicated repo networks (full scan of network_replicas).
      # CREATING and REPAIRING networks are treated optimistically, as if
      # they're about to come back.
      #
      # This means that a failed create or nw-repair that doesn't make it
      # to FAILED or DESTROYING state will stick around until the timeout
      # (1 hour), potentially delaying new-replica-creation operations.
      # The alternative is to be pessimistic and create lots of replicas
      # that turn out not to be needed.  I think repairs will be a lot
      # more frequent than failed repairs, so I'm optimistic here.
      #
      # Returns an array of tuples of [network_id, actual_count, target_count, attrs], where
      # attrs is either {voting: true} or {voting: false}.
      def self.get_bad_replica_counts(only_network_id: nil, limit: nil, ctx: nil)
        limit ||= network_query_limit
        ctx ||= NetworkMaintenanceContext.new

        slice = if only_network_id
          SliceQuery::OneIdSlice.new(only_network_id, ApplicationRecord::Domain::Repositories)
        else
          SliceQuery::Slice.new(slice_name: "bad-replica-counts", id_table: "repository_networks", domain_class: ApplicationRecord::Domain::Repositories, query_namespace: query_namespace, max_rss: GitHub.dgit_maint_max_rss)
        end

        results = get_slice_of_bad_replica_counts(slice, ctx: ctx)
        voting_counts, other_counts = limit_bad_replica_results(results, limit: limit, slice: slice)

        (voting_counts + other_counts).uniq.take(limit)
      end
      track_query_time :get_bad_replica_counts

      # Internal.
      #
      # Gets bad replica counts for the given slice of IDs.
      #
      # Returns nil if one of the slice-managed queries times out.
      # Otherwise, returns a hash of info => array of [nw/gist id, count, info]. e.g.
      #
      #   {
      #     {voting: true} => [ [1, 1, voting: true], [2, 4, voting: true] ],
      #     {voting: false} => [ [1, 0, voting: false] ]
      #   }
      def self.get_slice_of_bad_replica_counts(slice, ctx:)
        ids = ctx.get_slice_of_ids(slice)
        return nil if ids.nil?
        return {} if ids.empty?

        replicas = ctx.get_slice_of_replicas(slice)
        return nil if replicas.nil?

        strategy = ctx.make_replication_strategy(slice: slice)
        return nil if strategy.nil?

        bad_counts = Hash.new { |h, k| h[k] = [] }

        ids.each do |id|
          strategy.violations(id, replicas[id] || []).each do |violation|
            info = violation.last
            bad_counts[info].push(violation)
          end
        end

        bad_counts
      end

      # Internal.
      #
      # Puts the bad counts into the right order, applies the limit, and updates
      # the query slice based on the results.
      #
      # * all_bad_counts - the output of get_slice_of_bad_replica_counts
      # * limit - the highest number of items to return
      # * slice - the current query slice, which will be updated
      #
      # Returns two arrays, first the "important" (read: voting) results, then
      # the others. This is so that the caller can insert other results between
      # these two arrays.
      def self.limit_bad_replica_results(all_bad_counts, limit:, slice:)
        # If get_slice_of_bad_replica_counts returned nil, there's nothing to do here.
        return [[], []] if all_bad_counts.nil?

        voting_results = sort_bad_counts(all_bad_counts.delete(voting: true) || []).take(limit)
        if voting_results.size == limit
          next_offset = voting_results.map { |row| row[0] }.max
          slice.set_next_offset next_offset
        else
          slice.move_to_next_offset
        end

        other_results = []
        all_bad_counts.each do |_key, counts|
          remaining_limit = limit - voting_results.size - other_results.size
          break if remaining_limit < 1
          other_results += sort_bad_counts(counts).take(remaining_limit)
        end

        [voting_results, other_results]
      end

      def self.sort_bad_counts(counts)
        counts.sort_by { |_, copies, _, _| copies }
      end

      # Counts replicas for a gist, or for the next slice of gists.
      #
      # See get_bad_replica_counts for more about what this is looking for.
      #
      # Returns an array of tuples that looks like:
      #   [network_id, replica_count, target_count, info]
      # where 'info' is a hash with the following keys:
      #   :voting  - boolean, indicating whether the count is for voting replicas or
      #              non-voting replicas
      def self.get_bad_gist_replica_counts(only_gist_id: nil, limit: nil, ctx: nil)
        limit ||= gist_query_limit
        ctx ||= GistMaintenanceContext.new

        slice = if only_gist_id
          SliceQuery::OneIdSlice.new(only_gist_id, ApplicationRecord::Domain::Gists)
        else
          SliceQuery::Slice.new(slice_name: "bad-gist-replica-counts", id_table: "gists", domain_class: ApplicationRecord::Domain::Gists, query_namespace: query_namespace, max_rss: GitHub.dgit_maint_max_rss)
        end

        results = get_slice_of_bad_replica_counts(slice, ctx: ctx)
        voting_counts, other_counts = limit_bad_replica_results(results, limit: limit, slice: slice)

        (voting_counts + other_counts).uniq.take(limit)
      end
      track_query_time :get_bad_gist_replica_counts

      # Returns a set of of the networks in +network_ids+ which have any
      # replicas created in the last `MAX_TRANSIENT_TIME` seconds,
      # regardless of online-ness or state.  This is an indicator that the
      # network is undergoing some sort of migration or repair, and we
      # should allow it to have more than `GitHub.dgit_copies`.
      def self.recent_replicas(network_ids)
        return Set.new if network_ids.empty?

        res = Set.new
        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub::DGit::DB.each_network_db do |db|
            ids = db.SQL.results(<<-SQL, network_ids: network_ids, max_transient_time: MAX_TRANSIENT_TIME)
            SELECT network_id
              FROM network_replicas
             WHERE network_id IN :network_ids
               AND created_at > NOW() - INTERVAL :max_transient_time SECOND
            SQL
            res |= ids.flatten
          end
        end
        res
      end
      private_class_method :recent_replicas
      track_query_time :recent_replicas

      # Returns a set of networks out of the input list that had a
      # recent change to their storage state (e.g., recently frozen or
      # thawed).
      def self.recently_changed_storage_state(network_ids)
        return Set.new if network_ids.empty?

        res = Set.new
        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub::DGit::DB.each_network_db do |db|
            ids = db.SQL.results(<<-SQL, network_ids: network_ids, cutoff: 60)
            SELECT network_id
              FROM cold_networks
             WHERE network_id IN :network_ids
               AND updated_at > NOW() - INTERVAL :cutoff MINUTE
            SQL
            res |= ids.flatten
          end
        end
        res
      end
      private_class_method :recently_changed_storage_state
      track_query_time :recently_changed_storage_state

      def self.recent_gist_replicas(gist_ids)
        return Set.new if gist_ids.empty?

        res = Set.new
        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub::DGit::DB.each_gist_db do |db|
            ids = db.SQL.results(<<-SQL, gist_ids: gist_ids, max_transient_time: MAX_TRANSIENT_TIME)
            SELECT gist_id
              FROM gist_replicas
             WHERE gist_id IN :gist_ids
               AND created_at > NOW() - INTERVAL :max_transient_time SECOND
            SQL
            res |= ids.flatten
          end
        end
        res
      end
      private_class_method :recent_gist_replicas
      track_query_time :recent_gist_replicas

      # Return a Hash of repo_id -> network_id
      # for the given list of repo IDs.
      # If include_deleted is false, nothing will be returned for repo_ids
      # whose rows are marked non-`active`.
      def self.repo_ids_to_network_ids(repo_ids)
        sql = Arel.sql(<<-SQL, repo_ids: repo_ids)
          SELECT r.id,
                 r.source_id
            FROM repositories r
           WHERE r.id IN (:repo_ids)
        SQL
        Hash[ApplicationRecord::Domain::Repositories.connection.select_rows(sql)] # repo_id -> network_id
      end
      private_class_method :repo_ids_to_network_ids

      # Return the source ID for a given repository ID.
      def self.network_source_id_for(repo_id)
        result = repo_ids_to_network_ids([repo_id])
        result.empty? ? nil : result[repo_id]
      end

      def self.delete_repo_replicas_and_checksums(network_id, repo_id, repo_types = GitHub::DGit::RepoType::REPO_ISH)
        db = GitHub::DGit::DB.for_network_id(network_id)
        delete_repo_replicas_and_checksums_for_db(network_id, repo_id, repo_types, db)
      end

      def self.delete_repo_replicas_and_checksums_for_db(network_id, repo_id, repo_types, db)
        unless (repo_types == GitHub::DGit::RepoType::REPO_ISH) ||
                (repo_types == [GitHub::DGit::RepoType::REPO]) ||
                (repo_types == [GitHub::DGit::RepoType::WIKI])
          raise ArgumentError, "wrong repo_types given to #{__method__}"
        end

        ActiveRecord::Base.connected_to(role: :writing) do
          db.transaction do
            delete_repo_replicas(network_id, repo_id, repo_types: repo_types, db: db)
            delete_repo_checksums(network_id, repo_id, repo_types: repo_types, db: db)
          end # transaction
        end # connected_to
      end
      private_class_method :delete_repo_replicas_and_checksums_for_db

      def self.delete_repo_checksums(network_id, repo_id, db:, repo_types: GitHub::DGit::RepoType::REPO_ISH)
        ActiveRecord::Base.connected_to(role: :writing) do
          sql = db.SQL.new \
            network_id: network_id,
            repo_id: repo_id,
            repo_types: repo_types
          sql.add <<-SQL
            DELETE FROM repository_checksums
                  WHERE repository_id = :repo_id
                    AND repository_type IN :repo_types
          SQL
          sql.run
        end
      end

      def self.delete_repo_replicas(network_id, repo_id, db:, repo_types: GitHub::DGit::RepoType::REPO_ISH)
        ActiveRecord::Base.connected_to(role: :writing) do
          sql = db.SQL.new \
            network_id: network_id,
            repo_id: repo_id,
            repo_types: repo_types
          sql.add <<-SQL
            DELETE FROM repository_replicas
                  WHERE repository_id = :repo_id
                    AND repository_type IN :repo_types
          SQL
          sql.run
        end
      end

      def self.delete_wiki_replicas_and_checksums(network_id, repo_id)
        delete_repo_replicas_and_checksums(network_id, repo_id, [GitHub::DGit::RepoType::WIKI])
      end

      def self.delete_network_replicas(network_id)
        db = GitHub::DGit::DB.for_network_id(network_id)
        delete_network_replicas_for_db(network_id, db)
      end

      def self.delete_network_replicas_for_db(network_id, db)
        ActiveRecord::Base.connected_to(role: :writing) do
          db.transaction do
            db.SQL.run("DELETE FROM network_replicas WHERE network_id = :network_id",
                       network_id: network_id)
            GitHub::DGit::ColdStorage.remove_network_state(db, network_id)
          end # transaction
        end # connected_to
      end
      private_class_method :delete_network_replicas_for_db

      def self.delete_network_replica_for_host(network_id, host, ctx: NetworkMaintenanceContext.new)
        ctx.delete_replica_for_host(network_id, host)
      end

      def self.delete_gist_replicas_and_checksums(gist_id)
        gist_db = GitHub::DGit::DB.for_gist_id(gist_id)
        delete_gist_replicas_and_checksums_for_db(gist_id, gist_db)
      end

      def self.delete_gist_replicas_and_checksums_for_db(gist_id, db)
        ActiveRecord::Base.connected_to(role: :writing) do
          db.transaction do
            db.SQL.run(<<-SQL, gist_id: gist_id)
              DELETE FROM gist_replicas
                    WHERE gist_id = :gist_id
            SQL

            db.SQL.run(<<-SQL, gist_id: gist_id, repo_type: GitHub::DGit::RepoType::GIST)
              DELETE FROM repository_checksums
                    WHERE repository_id = :gist_id
                      AND repository_type = :repo_type
            SQL
          end
        end
      end
      private_class_method :delete_gist_replicas_and_checksums_for_db

      def self.delete_gist_replica_for_host(gist_id, host, ctx: GistMaintenanceContext.new)
        ctx.delete_replica_for_host(gist_id, host)
      end

      # Helpers for setting up initial data and tracking hashes.
      # Used by the network and gist maintenance jobs.
      class MaintenanceContext
        # Used when we want to filter out bad hosts per votingness
        attr_accessor :voting

        def initialize(voting: nil)
          @voting = voting
        end

        # Internal.
        def all_fileservers
          @all_fileservers ||= GitHub::DGit.get_fileservers(online_only: false)
        end

        # Return a string describing whether we are selecting voting, non-voting
        # or both kinds of servers. This is suitable for using with stat tags.
        def voting_s
          @voting.nil? ? "both" : voting.to_s
        end

        # All fileservers that don't vote on 3PC transactions.
        def non_voting_fs
          @non_voting_fs ||= all_fileservers.reject(&:contains_voting_replicas?)
        end

        # All non-voting fileservers that are allowed to receive new replicas.
        def non_voting_fs_for_new_replicas
          non_voting_fs.select(&:online?).reject(&:evacuating?).reject(&:embargoed?)
        end

        def online_fileservers
          all_fileservers.select(&:online?)
        end

        # All fileservers that vote on 3PC and that are online.
        def online_voting_fileservers
          @online_voting_fileservers ||= all_fileservers.select(&:contains_voting_replicas?).select(&:online?)
        end

        # Hostnames of voting fileservers.
        def online_voting_hosts
          online_voting_fileservers.map(&:name)
        end

        # All fileservers that are online.
        def online_hosts
          @online_hosts ||= all_fileservers.select(&:online?).map(&:name)
        end

        # All fileservers that are online and evacuating
        def evacuating_hosts
          @evacuating_hosts ||= online_fileservers.select(&:evacuating?).map(&:name)
        end

        # Where we want the work to be enqueued
        def queue_for(host)
          "maint_#{host}"
        end

        # Get a replication strategy
        #
        # This class returns the default strategy (e.g. 3 voting & 3
        # non-voting copies). Subclasses can return a strategy that knows
        # per-network or per-gist tricks, like for cold storage.
        #
        # Returns a strategy object
        def make_replication_strategy(**options)
          # The bad hosts list includes evacuating as well as non-existent host
          # that might have been left over. For the slicing operations we want
          # to exclude the evacuating ones but keep the non-existent ones in as
          # "bad". We also want to make sure that we include the evacuating
          # hosts in one of the "good" or "bad" lists.
          fs, bh =
              if options.fetch(:include_evacuating, false)
                [online_fileservers.reject(&:evacuating?), bad_hosts]
              else
                [online_fileservers, bad_hosts - evacuating_hosts]
              end
          ReplicationStrategy.new(fs, bad_hosts: bh, voting_strategy: options.fetch(:voting_strategy, nil), entity_type: entity_type)
        end

        def replica_count_helper(voting: nil, stale: nil, **)
          raise unless [voting, stale].compact.size == 1
          case
          when !voting.nil?
            if voting
              @replica_count_helper_voting ||= FixVotingReplicaCounts.new(self)
            else
              @replica_count_helper_nonvoting ||= FixNonVotingReplicaCounts.new(self)
            end
          when !stale.nil?
            @replica_count_helper_stale ||= FixStaleReplicaCounts.new(self, bad_hosts)
          else
            raise ArgumentError, "unrecognised helper required"
          end
        end

        # Initial count of queued jobs per fileserver.
        def queued_jobs
          @queued_jobs ||= Hash.new do |hash, host|
            # queue_depth returns 0 if the queue doesn't exist, so the default value is 0.
            hash[host] = ApplicationJob.queue_adapter.queue_depth(queue: queue_for(host))
          end
        end

        # Count of new jobs per fileserver.
        def jobs_per_host
          @jobs_per_host ||= Hash.new(0)
        end

        # Is it ok to queue something up for this host?
        def ok_to_queue_job?(host, increment: false)
          count = queued_jobs[host] + jobs_per_host[host]
          if count >= MAX_JOBS_PER_HOST
            tags = ["maint:#{entity}", "target_host:#{host}"]
            GitHub.dogstats.increment("dgit.maintenance.queue_full", tags: tags)
            return false
          end
          jobs_per_host[host] += 1 if increment
          true
        end

        def get_slice_of_ids(slice)
          slice.querying do
            ActiveRecord::Base.connected_to(role: :reading) do
              sql_bindings = {
                table: Arel.sql(id_table.to_s),
                offset: slice.offset,
                next_offset: slice.next_offset,
              }
              sql = Arel.sql <<-SQL, **sql_bindings
                SELECT id
                  FROM :table
                 WHERE id > :offset
                   AND id <= :next_offset
              SQL
              slice.domain_class.connection.select_rows(sql).flatten
            end
          end
        end

        def get_slice_of_replicas(slice)
          replicas = []
          GitHub::DGit::DB.each_network_db do |db|
            results = slice.querying do
              sql = db.SQL.new \
                table: GitHub::SQL.LITERAL(replica_table),
                id_col: GitHub::SQL.LITERAL("#{entity}_id"),
                offset: slice.offset,
                next_offset: slice.next_offset
              sql.add <<-SQL
                SELECT :id_col, host, state
                  FROM :table
                 WHERE :id_col > :offset
                   AND :id_col <= :next_offset
              SQL
              sql.results
            end
            if results.nil?
              return nil
            else
              replicas += results
            end
          end
          replicas = replicas.group_by(&:first)
        end

      end

      class NetworkMaintenanceContext < MaintenanceContext
        def entity
          "network"
        end

        def entity_type
          GitHub::DGit::RepoType::NETWORK
        end

        def id_table
          "repository_networks"
        end

        def replica_table
          "network_replicas"
        end

        # All hosts currently considered bad
        def bad_hosts
          @bad_hosts ||= GitHub::DGit::Maintenance.get_bad_network_replica_hosts(ctx: self)
        end

        def get_slice_of_storage_states(slice)
          aggregate_results = Hash.new(0)
          ActiveRecord::Base.connected_to(role: :reading) do
            slice.querying do
              GitHub::DGit::DB.each_network_db do |db|
                sql = db.SQL.new \
                  offset: slice.offset,
                  next_offset: slice.next_offset
                sql.add <<-SQL
                  SELECT cn.network_id, cn.state
                    FROM cold_networks cn
                   WHERE cn.network_id > :offset
                     AND cn.network_id <= :next_offset
                SQL
                aggregate_results.merge!(sql.results.to_h)
              end
            end
          end
          aggregate_results
        end

        # Returns a cold-storage-aware replication strategy
        def make_replication_strategy(**options)
          slice = options.delete(:slice)
          storage_states = options.delete(:storage_states)

          storage_states ||= get_slice_of_storage_states(slice)
          return nil if storage_states.nil?

          # For networks that aren't in cold storage, we use the default strategy, augmented
          # with a counter driving copies on HDD servers to zero.  When a network is warmed,
          # this is what cleans up any left-over replicas on HDD servers.
          cfs = GitHub::DGit.get_fileservers(storage_class: :hdd).reject(&:evacuating?).index_by(&:name)
          non_cold_storage_strategy = ReplicationStrategy::Multi.new \
              ReplicationStrategy::ReplicaCounter.new(fileservers: cfs, copies: 0, states: nil, cold_storage: true, datacenter: nil),
              super(**options)

          # If we include the evacuating hosts as bad, then we do not want to
          # include them in the list of fileservers where it's fine to have a
          # replica.
          fs = GitHub::DGit.get_fileservers(storage_class: :all)
          if options.fetch(:include_evacuating, false)
            fs = fs.reject(&:evacuating?)
          end

          # For networks that are in cold storage, we use the cold storage counter injected
          # into the default strategy in place of the normal voting-replicas counter.  This
          # continues to mix up the ideas of datacenters (for cold storage) and voting/non
          # groups of fileservers.  We'll need to revisit this as we continue to evolve our
          # datacenter plans.
          cold_storage_counter = ReplicationStrategy::ColdStorageCounter.new(fileservers: fs, datacenters: GitHub::DGit.cold_storage_dcs)
          cold_storage_strategy = super(**options.merge({ voting_strategy: cold_storage_counter }))

          # Finally, compose the two strategies together, based on whether
          # the network of interest is in cold storage or not
          ReplicationStrategy::LazyStrategy.new do |id, _r|
            if storage_states[id] == 1
              cold_storage_strategy
            else
              non_cold_storage_strategy
            end
          end
        end

        def replica_count_helper(**options)
          if options.has_key? :cold_storage
            @replica_count_helper_cold ||= Hash.new { |h, k| h[k] = FixColdStorageCounts.new(self, **k) }
            @replica_count_helper_cold[options]
          else
            super
          end
        end

        def all_replicas(network_id)
          GitHub::DGit::Routing.all_network_replicas(network_id)
        end

        def enqueue_create_replica(network_id, host)
          GitHub.logger.info("enqueueing network replica creation",
                             "code.function" => "enqueue_create_replica",
                             "gh.repo.network_id" => network_id,
                             "gh.spokes.fileserver" => host)
          SpokesCreateNetworkReplicaJob.set(queue: queue_for(host)).perform_later(network_id, host)
        end

        def enqueue_move_replica(network_id, from_host, to_host)
          GitHub.logger.info("enqueueing move of network replica",
                             "code.function" => "enqueue_move_replica",
                             "gh.repo.network_id" => network_id,
                             "gh.spokes.repairs.src_replica" => from_host,
                             "gh.spokes.repairs.dst_replica" => to_host)
          SpokesMoveNetworkReplicaJob.set(queue: queue_for(to_host)).perform_later(network_id, from_host, to_host, Time.now.to_i)
        end

        def enqueue_destroy_replica(network_id, host)
          GitHub.logger.info("enqueueing network replica deletion",
                             "code.function" => "enqueue_destroy_replica",
                             "gh.repo.network_id" => network_id,
                             "gh.spokes.fileserver" => host)
          set_replica_state(network_id, host, DESTROYING)
          SpokesDestroyNetworkReplicaJob.set(queue: queue_for(host)).perform_later(network_id, host)
        end

        def rebalance_read_weight(network_id, new_host: nil, replicas: nil)
          rebalancer = GitHub::DGit::Rebalancer::Network.new(network_id, new_host: new_host, replicas: replicas)
          rebalancer.rebalance
        end

        def set_replica_state(network_id, host, new_state, prior_state = nil, update_time = true)
          tags = ["kind:network", "new_state:#{new_state}"]
          if prior_state
            tags << "prior_state:#{prior_state}"
          end
          GitHub.dogstats.increment("dgit.set_replica_state", tags: tags)
          ActiveRecord::Base.connected_to(role: :writing) do
            sql = GitHub::DGit::DB.for_network_id(network_id).SQL.new \
              network_id: network_id,
              host: host,
              new_state: new_state
            sql.add <<-SQL
              UPDATE network_replicas
              SET state=:new_state
            SQL
            sql.add(", updated_at=NOW()") if update_time
            sql.add("WHERE network_id=:network_id AND host=:host")
            sql.add("AND state IN :prior", prior: [prior_state].flatten) if prior_state
            sql.run
            return sql.affected_rows == 1
          end
        end

        def delete_replica_for_host(network_id, host)
          ActiveRecord::Base.connected_to(role: :writing) do
            db = GitHub::DGit::DB.for_network_id(network_id)
            db.SQL.run(<<-SQL, network_id: network_id, host: host)
              DELETE FROM network_replicas
                WHERE network_id=:network_id AND host=:host
            SQL
          end
        end

        def load_recently_changed_storage_state(network_ids)
          @recently_changed_storage_state = Maintenance.recently_changed_storage_state(network_ids)
        end

        def load_recent_replicas(network_ids)
          @recent_replicas = Maintenance.recent_replicas(network_ids)
        end

        def holdoff_replica_creation?(network_id)
          raise "no recently changed storage state set loaded" unless @recently_changed_storage_state
          @recently_changed_storage_state.include?(network_id)
        end

        def holdoff_replica_destruction?(network_id)
          raise "no recently changed storage state set loaded" unless @recently_changed_storage_state
          raise "no recent replicas set loaded" unless @recent_replicas
          @recent_replicas.include?(network_id) || @recently_changed_storage_state.include?(network_id)
        end
      end

      class GistMaintenanceContext < MaintenanceContext
        def entity
          "gist"
        end

        def entity_type
          GitHub::DGit::RepoType::GIST
        end

        def id_table
          "gists"
        end

        def replica_table
          "gist_replicas"
        end

        # All hosts currently considered bad
        def bad_hosts
          @bad_hosts ||= GitHub::DGit::Maintenance.get_bad_gist_replica_hosts(ctx: self)
        end

        def all_replicas(gist_id)
          GitHub::DGit::Routing.all_gist_replicas(gist_id)
        end

        def enqueue_create_replica(gist_id, host)
          GitHub.logger.info("enqueueing gist replica creation",
                             "code.function" => "enqueue_create_replica",
                             "gh.gist.id" => gist_id,
                             "gh.spokes.fileserver" => host)
          SpokesCreateGistReplicaJob.set(queue: queue_for(host)).perform_later(gist_id, host)
        end

        def enqueue_move_replica(gist_id, from_host, to_host)
          GitHub.logger.info("enqueueing move of gist replica",
                             "code.function" => "enqueue_move_replica",
                             "gh.gist.id" => gist_id,
                             "from_host" => from_host,
                             "to_host" => to_host)
          SpokesMoveGistReplicaJob.set(queue: queue_for(to_host)).perform_later(gist_id, from_host, to_host, Time.now.to_i)
        end

        def enqueue_destroy_replica(gist_id, host)
          GitHub.logger.info("enqueueing gist replica deletion",
                             "code.function" => "enqueue_destroy_replica",
                             "gh.gist.id" => gist_id,
                             "gh.spokes.fileserver" => host)
          set_replica_state(gist_id, host, DESTROYING)
          SpokesDestroyGistReplicaJob.set(queue: queue_for(host)).perform_later(gist_id, host)
        end

        def rebalance_read_weight(gist_id, replicas: nil)
          rebalancer = Rebalancer::Gist.new(gist_id, replicas: replicas)
          rebalancer.rebalance
        end

        def set_replica_state(gist_id, host, new_state, prior_state = nil, update_time = true)
          tags = ["kind:gist", "new_state:#{new_state}"]
          if prior_state
            tags << "prior_state:#{prior_state}"
          end
          GitHub.dogstats.increment("dgit.set_replica_state", tags: tags)
          ActiveRecord::Base.connected_to(role: :writing) do
            sql = GitHub::DGit::DB.for_gist_id(gist_id).SQL.new \
              gist_id: gist_id,
              host: host,
              new_state: new_state
            sql.add <<-SQL
              UPDATE gist_replicas
              SET state=:new_state
            SQL
            sql.add(", updated_at=NOW()") if update_time
            sql.add("WHERE gist_id=:gist_id AND host=:host")
            sql.add("AND state=:prior", prior: prior_state) if prior_state
            sql.run
            return sql.affected_rows == 1
          end
        end

        def delete_replica_for_host(gist_id, host)
          ActiveRecord::Base.connected_to(role: :writing) do
            db = GitHub::DGit::DB.for_gist_id(gist_id)
            db.SQL.run(<<-SQL, gist_id: gist_id, host: host)
              DELETE gist_replicas FROM gist_replicas
                WHERE gist_replicas.gist_id=:gist_id
                  AND gist_replicas.host=:host
            SQL
          end
        end

        def load_recently_changed_storage_state(gist_ids)
          # no-op
        end

        def load_recent_replicas(gist_ids)
          @recent_replicas = Maintenance.recent_gist_replicas(gist_ids)
        end

        def holdoff_replica_creation?(gist_id)
          false
        end

        def holdoff_replica_destruction?(gist_id)
          raise "no recent replicas set loaded" unless @recent_replicas
          @recent_replicas.include?(gist_id)
        end
      end

      module LoadAwarePicker
        def pick_hosts(count, old_replicas)
          filtered_old_replicas = filter_replicas(old_replicas)
          old_fileservers = filtered_old_replicas.map(&:fileserver)
          too_busy_fileservers = []
          ok_fileservers = []
          while count > 0
            candidates = pick_some_candidate_fileservers(count, current_fileservers: old_fileservers, chosen_fileservers: ok_fileservers, too_busy_fileservers: too_busy_fileservers)
            break if candidates.empty?
            candidates.each do |fs|
              if !@ctx || @ctx.ok_to_queue_job?(fs.name, increment: true)
                ok_fileservers << fs
                count -= 1
              else
                too_busy_fileservers << fs
              end
            end
          end
          ok_fileservers.map(&:name)
        end

        def pick_some_candidate_fileservers(count, current_fileservers:, chosen_fileservers:, too_busy_fileservers:)
          excluded_hosts = (current_fileservers + chosen_fileservers + too_busy_fileservers).map(&:name)
          far_from_fs = current_fileservers + chosen_fileservers
          HostPicker.new.pick_fileservers(count, fileserver_pool: fileservers_for_new_replicas, exclusions: excluded_hosts, far_from: far_from_fs, no_raise: true)
        end
      end

      class FixVotingReplicaCounts
        def initialize(ctx)
          @ctx = ctx
        end

        attr_reader :ctx

        def filter_replicas(replicas)
          replicas.select(&:voting?)
        end

        include LoadAwarePicker
        def fileservers_for_new_replicas
          @fs_for_new_replicas ||= GitHub::DGit.get_fileservers(voting_only: true, exclude_embargoed: true)
        end
      end

      class FixNonVotingReplicaCounts
        def initialize(ctx)
          @ctx = ctx
        end

        attr_reader :ctx

        def filter_replicas(replicas)
          replicas.reject(&:voting?)
        end

        include LoadAwarePicker
        def fileservers_for_new_replicas
          @fs_for_new_replicas ||= ctx.non_voting_fs_for_new_replicas
        end

        def pick_some_candidate_fileservers(count, current_fileservers:, chosen_fileservers:, too_busy_fileservers:)
          candidates = super(count, current_fileservers: current_fileservers, chosen_fileservers: chosen_fileservers, too_busy_fileservers: too_busy_fileservers)
          candidates = candidates.group_by(&:datacenter)
          current_datacenters = current_fileservers.map(&:datacenter).uniq
          new_datacenters = chosen_fileservers.map(&:datacenter).uniq

          ok_candidates = []
          candidates.each_key do |dc|
            if current_datacenters.include?(dc)
              ok_candidates += candidates[dc]
            elsif new_datacenters.include?(dc)
              # There's already going to be a new replica in 'dc',
              # so don't add anymore (yet).
            else
              # There aren't any replicas in 'dc' yet, so create the
              # first one now.
              ok_candidates << candidates[dc].first
            end
          end

          ok_candidates
        end
      end

      class FixStaleReplicaCounts
        def initialize(ctx, bad_fs)
          @ctx = ctx
          @bad_fs = bad_fs
        end

        attr_reader :ctx

        def filter_replicas(replicas)
          replicas.select { |r| @bad_fs.include?(r.fileserver.name) }
        end
      end

      class FixColdStorageCounts
        def initialize(ctx, cold_storage:, datacenter:)
          @ctx = ctx
          @cold_storage = cold_storage
          @datacenters = datacenter.nil? ? nil : [datacenter]
          @storage_class = cold_storage ? :hdd : :ssd
        end

        attr_reader :ctx

        def filter_replicas(replicas)
          replicas.select { |r| r.hdd_storage? == @cold_storage }
                  .select { |r| @datacenters.nil? || @datacenters.include?(r.datacenter) }
        end

        include LoadAwarePicker
        def fileservers_for_new_replicas
          @fs_for_new_replicas ||= GitHub::DGit.get_fileservers(exclude_embargoed: true, in_datacenters: @datacenters, storage_class: @storage_class)
        end
      end
    end  # GitHub::DGit::Maintenance
  end  # GitHub::DGit
end  # GitHub
