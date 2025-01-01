# typed: false
# frozen_string_literal: true

# A handful of utility functions for Spokes, including its scripts.
# Please keep this file safe for `require ... config/basic` use in
# scripts, by not using ActiveRecord objects.

require "github/config/mysql"

module GitHub
  class DGit
    class Util
      def self.is_evacuating?(host)
        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub::DGit::DB::FS::SQL.value("SELECT evacuating FROM fileservers WHERE host=:host", host: host).to_i > 0
        end
      end

      def self.is_online?(host)
        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub::DGit::DB::FS::SQL.value("SELECT online FROM fileservers WHERE host = :host", host: host).to_i > 0
        end
      end

      def self.set_fileserver_evacuating(host, reason)
        rows_changed = rows_expected = 0
        GitHub::DGit::DB.each_fileserver_db.each do |db|
          rows_expected += 1
          rows_changed += db.SQL.run(<<-SQL, host: host, reason: reason).affected_rows
            UPDATE fileservers
               SET embargoed = 1, evacuating = 1, evacuating_reason = :reason, embargoed_reason = :reason
             WHERE host = :host
          SQL
        end # each_fileserver_db
        rows_changed == rows_expected
      end

      def self.unset_fileserver_evacuating(host)
        rows_changed = rows_expected = 0
        GitHub::DGit::DB.each_fileserver_db.each do |db|
          rows_expected += 1
          rows_changed += db.SQL.run("UPDATE fileservers SET evacuating = 0, evacuating_reason = NULL WHERE host = :host",
                                     host: host).affected_rows
        end # each_fileserver_db
        rows_changed == rows_expected
      end

      def self.set_fileserver_embargoed(host, reason)
        rows_changed = rows_expected = 0
        GitHub::DGit::DB.each_fileserver_db.each do |db|
          rows_expected += 1
          rows_changed += db.SQL.run(<<-SQL, host: host, reason: reason).affected_rows
            UPDATE fileservers
               SET embargoed = 1, embargoed_reason = :reason
             WHERE host = :host
          SQL
        end # each_fileserver_db
        rows_changed == rows_expected
      end

      def self.unset_fileserver_embargoed(host)
        rows_changed = rows_expected = 0
        GitHub::DGit::DB.each_fileserver_db.each do |db|
          rows_expected += 1
          rows_changed += db.SQL.run("UPDATE fileservers SET embargoed = 0, embargoed_reason = NULL WHERE host = :host",
                                     host: host).affected_rows
        end # each_fileserver_db
        rows_changed == rows_expected
      end

      def self.set_fileserver_quiescing(host, reason)
        rows_changed = rows_expected = 0
        GitHub::DGit::DB.each_fileserver_db.each do |db|
          rows_expected += 1
          rows_changed += db.SQL.run(<<-SQL, host: host, reason: reason).affected_rows
            UPDATE fileservers
               SET quiescing = 1, quiescing_reason = :reason
             WHERE host = :host
          SQL
        end # each_fileserver_db
        rows_changed == rows_expected
      end

      def self.unset_fileserver_quiescing(host)
        rows_changed = rows_expected = 0
        GitHub::DGit::DB.each_fileserver_db.each do |db|
          rows_expected += 1
          rows_changed += db.SQL.run("UPDATE fileservers SET quiescing = 0, quiescing_reason = NULL WHERE host = :host",
                                     host: host).affected_rows
        end # each_fileserver_db
        rows_changed == rows_expected
      end

      def self.set_fileserver_nonvoting(host, non_voting)
        rows_changed = rows_expected = 0
        GitHub::DGit::DB.each_fileserver_db do |db|
          rows_expected += 1
          rows_changed += db.SQL.run("UPDATE fileservers SET non_voting = :non_voting WHERE host = :host",
                                     host: host, non_voting: non_voting).affected_rows
        end # each_fileserver_db
        rows_changed == rows_expected
      end

      def self.set_fileserver_location(host, datacenter, site, rack = nil)
        rows_changed = rows_expected = 0
        GitHub::DGit::DB.each_fileserver_db do |db|
          rows_expected += 1
          rows_changed += db.SQL.run("UPDATE fileservers SET datacenter = :datacenter, rack = :rack, site = :site WHERE host = :host",
                                     host: host, datacenter: datacenter, rack: rack || GitHub::SQL::NULL, site: site).affected_rows
        end # each_fileserver_db
        rows_changed == rows_expected
      end

      def self.set_fileserver_online(host)
        rows_changed = rows_expected = 0
        GitHub::DGit::DB.each_fileserver_db do |db|
          rows_expected += 1
          rows_changed += db.SQL.run("UPDATE fileservers SET online = 1 WHERE host = :host",
                                     host: host).affected_rows
        end # each_fileserver_db
        rows_changed == rows_expected
      end

      def self.set_fileserver_offline(host)
        rows_changed = rows_expected = 0
        GitHub::DGit::DB.each_fileserver_db do |db|
          rows_expected += 1
          rows_changed += db.SQL.run("UPDATE fileservers SET online = 0 WHERE host = :host",
                                     host: host).affected_rows
        end # each_fileserver_db
        rows_changed == rows_expected
      end

      def self.set_fileserver_cache_location(host, cache_location)
        rows_changed = rows_expected = 0
        GitHub::DGit::DB.each_fileserver_db do |db|
          rows_expected += 1
          rows_changed += db.SQL.run("UPDATE fileservers SET cache_location = :cache_location WHERE host = :host",
                                     cache_location: cache_location, host: host).affected_rows
        end # each_fileserver_db
        rows_changed == rows_expected
      end

      def self.delete_fileserver(host)
        rows_changed = rows_expected = 0
        GitHub::DGit::DB.each_fileserver_db.each do |db|
          rows_expected += 1
          rows_changed += db.SQL.run("DELETE FROM fileservers WHERE host = :host",
                                            host: host).affected_rows
        end # each_fileserver_db
        rows_changed == rows_expected
      end

      def self.set_fileserver_hdd_storage(host)
        rows_changed = rows_expected = 0
        GitHub::DGit::DB.each_fileserver_db do |db|
          rows_expected += 1
          rows_changed += db.SQL.run("UPDATE fileservers SET hdd_storage = 1 WHERE host = :host",
                                     host: host).affected_rows
        end # each_fileserver_db
        rows_changed == rows_expected
      end

      def self.set_fileserver_ssd_storage(host)
        rows_changed = rows_expected = 0
        GitHub::DGit::DB.each_fileserver_db do |db|
          rows_expected += 1
          rows_changed += db.SQL.run("UPDATE fileservers SET hdd_storage = 0 WHERE host = :host",
                                     host: host).affected_rows
        end # each_fileserver_db
        rows_changed == rows_expected
      end

      REPLICA_DELETE_BATCH_SIZE = 100 # delete at most this many SQL rows at a time

      def self.delete_gist_replica_records(host)
        done = false
        total_deleted = 0
        GitHub::DGit::DB.each_gist_db do |db|
          while !done
            db.throttle do
              sql = db.SQL.new \
                host: host,
                limit: REPLICA_DELETE_BATCH_SIZE
              sql.add "DELETE FROM gist_replicas WHERE host = :host LIMIT :limit"
              sql.run
              total_deleted += sql.affected_rows
              done = sql.affected_rows < REPLICA_DELETE_BATCH_SIZE
            end # db.throttle
          end # while !done
        end # each_gist_db
        total_deleted
      end

      def self.delete_network_replica_records(host)
        done = false
        total_deleted = 0
        GitHub::DGit::DB.each_network_db do |db|
          while !done
            db.throttle do
              sql = db.SQL.new \
                host: host,
                limit: REPLICA_DELETE_BATCH_SIZE
              sql.add "DELETE FROM network_replicas WHERE host = :host LIMIT :limit"
              sql.run
              total_deleted += sql.affected_rows
              done = sql.affected_rows < REPLICA_DELETE_BATCH_SIZE
            end # db.throttle
          end # while !done
        end # each_network_db
        total_deleted
      end

      def self.delete_repo_replica_records(host)
        done = false
        total_deleted = 0
        GitHub::DGit::DB.each_network_db do |db|
          while !done
            db.throttle do
              sql = db.SQL.new \
                host: host,
                limit: REPLICA_DELETE_BATCH_SIZE
              sql.add "DELETE FROM repository_replicas WHERE host = :host LIMIT :limit"
              sql.run
              total_deleted += sql.affected_rows
              done = sql.affected_rows < REPLICA_DELETE_BATCH_SIZE
            end # db.throttle
          end # while !done
        end # each_network_db
        total_deleted
      end

      def self.remaining_gists_on_host(host)
        total_count = 0
        GitHub::DGit::DB.each_gist_db do |db|
          ActiveRecord::Base.connected_to(role: :reading) do
            count = db.SQL.value("SELECT COUNT(*) FROM gist_replicas WHERE host = :host",
                                 host: host)
            total_count += count unless count.nil?
          end # connected_to
        end # each_gist_db
        total_count
      end

      def self.remaining_networks_on_host(host)
        total_count = 0
        GitHub::DGit::DB.each_network_db do |db|
          ActiveRecord::Base.connected_to(role: :reading) do
            count = db.SQL.value("SELECT COUNT(*) FROM network_replicas WHERE host = :host",
                                 host: host)
            total_count += count unless count.nil?
          end # connected_to
        end # each_network_db
        total_count
      end

      def self.raw_fileserver_rows
        rows = GitHub::DGit::DB::FS::SQL.hash_results(<<-SQL)
          SELECT host, ip, online, embargoed, embargoed_reason, quiescing, quiescing_reason, evacuating, evacuating_reason, datacenter, rack, non_voting, hdd_storage
            FROM fileservers
        SQL
        rows.map { |row| Hash[row.map { |name, col| [name, col.is_a?(Integer) ? col > 0 : col] }] }
      end

      def self.raw_fileserver_rows_for_host(host)
        GitHub::DGit::Util.raw_fileserver_rows.select { |row| row["host"] == host }
      end

      def self.all_fileserver_hosts
        GitHub::DGit::Util.raw_fileserver_rows.map { |row| row["host"] }
      end

      def self.offline_fileserver_hosts
        GitHub::DGit::Util.raw_fileserver_rows.reject { |row| row["online"] }.map { |row| row["host"] }
      end

      def self.online_gist_replica_hosts(gist_id)
        GitHub::DGit::DB.for_gist_id(gist_id).SQL.results(<<-SQL, gist_id: gist_id).flatten
          SELECT gist_replicas.host
            FROM gist_replicas, fileservers
           WHERE gist_replicas.gist_id = :gist_id
             AND gist_replicas.host = fileservers.host
             AND fileservers.online
        SQL
      end

      def self.online_network_replica_hosts(network_id)
        GitHub::DGit::DB.for_network_id(network_id).SQL.results(<<-SQL, network_id: network_id).flatten
          SELECT network_replicas.host
            FROM network_replicas, fileservers
           WHERE network_replicas.network_id = :network_id
             AND network_replicas.host = fileservers.host
             AND fileservers.online
        SQL
      end

      def self.gist_replicas_summary(gist_id)
        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub::DGit::DB.for_gist_id(gist_id).SQL.hash_results(<<-SQL, gist_id: gist_id, repo_type: GitHub::DGit::RepoType::GIST)
            SELECT gr.host,
                   gr.state,
                   fs.online,
                   fs.non_voting,
                   rc.checksum AS expected,
                   gr.checksum AS actual
              FROM gist_replicas gr
              LEFT JOIN fileservers fs ON fs.host = gr.host
              LEFT JOIN repository_checksums rc ON gr.gist_id = rc.repository_id
                                               AND rc.repository_type = :repo_type
             WHERE gr.gist_id = :gist_id
          SQL
        end # connected_to
      end

      def self.repo_replicas_summary(network_id, repo_id, repo_type)
        ActiveRecord::Base.connected_to(role: :reading) do
          sql = GitHub::DGit::DB.for_network_id(network_id).SQL.new \
                  network_id: network_id, \
                  repo_id: repo_id, \
                  repo_type: repo_type
          sql.add <<-SQL
            SELECT nr.host,
                   nr.state,
                   fs.online,
                   fs.non_voting,
                   rc.checksum AS expected,
                   rr.checksum AS actual
              FROM network_replicas nr
              LEFT JOIN fileservers fs ON fs.host = nr.host
              LEFT JOIN repository_checksums rc ON rc.repository_id=:repo_id
                                               AND rc.repository_type=:repo_type
              LEFT JOIN repository_replicas rr  ON rr.repository_id=:repo_id
                                               AND rr.repository_type=:repo_type
                                               AND rr.host=nr.host
             WHERE nr.network_id=:network_id
          SQL
          sql.hash_results
        end # connected_to
      end

      def self.network_ids_on_hosts(hosts)
        ActiveRecord::Base.connected_to(role: :reading) do
          result_set = Set.new
          GitHub::DGit::DB.each_network_db do |db|
            sql = db.SQL.new("SELECT network_id FROM network_replicas WHERE host=:host", host: hosts[0])
            hosts[1..-1].each do |h|
              sql.add("AND network_id IN (SELECT network_id FROM network_replicas WHERE host=:host)", host: h)
            end
            result_set << sql.results.flatten
          end # each_network_db
          result_set.to_a.flatten
        end # connected_to
      end

      def self.gist_ids_on_hosts(hosts)
        ActiveRecord::Base.connected_to(role: :reading) do
          result_set = Set.new
          GitHub::DGit::DB.each_gist_db do |db|
            first_host, *rest_of_hosts = hosts
            sql = db.SQL.new("SELECT gist_id FROM gist_replicas WHERE host=:host", host: first_host)
            rest_of_hosts.each do |h|
              sql.add("AND gist_id IN (SELECT gist_id FROM gist_replicas WHERE host=:host)", host: h)
            end
            result_set << sql.results.flatten
          end
          result_set.to_a.flatten
        end
      end

      # Returns the most common checksum, if there's a clear majority.
      # Returns nil otherwise.
      #  - hash = a hash of { host => checksum, host => checksum, ... }
      def self.get_majority(hash)
        sums = hash.values   # [ 'aaa', 'bbb', 'aaa' ]
        return if sums.empty?
        collate = sums.group_by { |x| x }.map { |k, v| [k, v.size] }.sort_by { |x| -x[1] }  # [['aaa', 2], ['bbb', 1]]
        return collate.first.first if collate.size == 1                # unanimous agreement
        return collate.first.first if collate[0][1] > collate[1][1]  # clear majority
        nil                                                          # no majority
      end

      # Return a list of repo IDs for the given network ID.
      def self.repo_ids_for(network_id, include_deleted: true, include_archived: false, include_spokes: false)
        raise "`include_archived` is an enterprise-only option" if include_archived && !GitHub.enterprise?
        sql = Arel.sql <<-SQL, network_id: network_id
          SELECT id
          FROM repositories
          WHERE source_id = :network_id
        SQL
        sql += Arel.sql "AND active" unless include_deleted

        monolith_repos = ApplicationRecord::Domain::Repositories.connection.select_rows(sql).flatten

        # include repositories that exist in spokes, but not the monolith.
        # Theoretically spokes should always agree with the monolith, but
        # sometimes repositories get deleted in the monolith, but not in
        # spokes. Including the repositories that are only in spokes allows
        # us to properly handle and replicate these partially deleted
        # repositories.
        if include_spokes
          all_repos = monolith_repos.to_set

          # Theoretically, we should only need to look up the repository IDs
          # using a single (active) network replica. However, here we repeat
          # the query for each network replica to maintain parity with what
          # was here before, and to cover the edge case where a repository is
          # missing a subset of replicas.
          network_replicas(network_id).each do |network_replica_id, _, _|
            each_repository_replica_for_network_replica(network_id, network_replica_id) do |repo_id, _, _, _|
              all_repos.add(repo_id)
            end
          end

          all_repos.to_a
        else
          monolith_repos
        end
      end

      # Iterate over each network replica in the network. The provided block
      # is called with |network_replica_id, host, state|.
      def self.network_replicas(network_id)
        db = GitHub::DGit::DB.for_network_id(network_id)

        db.SQL.results(<<-SQL, network_id: network_id)
          SELECT id, host, state
          FROM network_replicas
          WHERE network_id = :network_id
        SQL
      end

      # Iterate over each repository ID with a replica that matches the
      # specified network_replica_id.
      def self.each_repository_replica_for_network_replica(network_id, network_replica_id)
        db = GitHub::DGit::DB.for_network_id(network_id)

        last_id = 0
        limit = 10000

        loop do
          binds = {
            network_id: network_id,
            network_replica_id: network_replica_id,
            last_id: last_id,
            limit: limit
          }

          results = db.SQL.results(<<-SQL, **binds)
            SELECT id, repository_id, repository_type, updated_at, checksum
            FROM repository_replicas
            WHERE network_replica_id = :network_replica_id
            AND id > :last_id
            ORDER BY id
            LIMIT :limit
          SQL

          results.each do |_, repository_id, repository_type, updated_at, checksum|
            yield repository_id, repository_type, updated_at, checksum
          end

          if results.count < limit
            break
          end

          last_id = results.last[0]
        end
      end

      def self.default_cache_replica_counts(entity_type)
        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub::DGit::DB::FS::SQL.results(<<-SQL, entity_type: entity_type)
            SELECT cache_location, number_of_replicas
              FROM cache_storage_policies
             WHERE entity_type = :entity_type
               AND entity_id = 0
          SQL
        end
      end

      def self.min_cache_replica_count(entity_type, cache_location)
        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub::DGit::DB::FS::SQL.value(<<-SQL, entity_type: entity_type, cache_location: cache_location).to_i
            SELECT MIN(number_of_replicas)
              FROM cache_storage_policies
             WHERE entity_type = :entity_type
               AND cache_location = :cache_location
               AND number_of_replicas > 0
          SQL
        end
      end

      # May return nil if no replica count is set for the specific entity.
      def self.cache_replica_count(entity_type, entity_id, cache_location)
        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub::DGit::DB::FS::SQL.value(<<-SQL, entity_type: entity_type, entity_id: entity_id, cache_location: cache_location)
            SELECT number_of_replicas
              FROM cache_storage_policies
             WHERE entity_type = :entity_type
               AND entity_id = :entity_id
               AND cache_location = :cache_location
          SQL
        end
      end

      def self.load_datacenter_regions
        ActiveRecord::Base.connected_to(role: :reading) do
          @@datacenter_regions = begin
            sql = GitHub::DGit::DB::DC::SQL.run("SELECT datacenter, region FROM datacenters")
            sql.results.to_h
          rescue ActiveRecord::StatementInvalid
            raise if !GitHub.enterprise?
            # During GHE upgrade, dgit-cluster-restore-routes can get here
            # before migrations have run.  If the table doesn't exist yet,
            # treat it as empty.
            {}
          end
        end
      end

      def self.datacenter_region(dc)
        @@datacenter_regions ||= self.load_datacenter_regions
        @@datacenter_regions[dc]
      end

      def self.maintenance_status(network_id)
        ApplicationRecord::Domain::Repositories.connection.select_value(Arel.sql("SELECT maintenance_status FROM repository_networks WHERE id = :network_id",
                          network_id: network_id))
      end

      def self.long_host(str)
        return unless str
        str.sub(/\Adfs-?[0-9a-f]+\z/, 'github-\0')
      end

      def self.config_store(repository, name, value)
        GitHub::DGit::with_dgit_lock(repository) do
          repository.rpc.config_store(name, value)
        end
      end

      def self.config_delete(repository, name)
        GitHub::DGit::with_dgit_lock(repository) do
          repository.rpc.config_delete(name)
        end
      end

      def self.make_gitrpc(url)
        if !GitHub.enterprise? && url.start_with?("bertrpc:")
          @@spokesd_client ||= GitHub::Spokes::Client::Spokesd.instance
          ::GitRPC.new(url, spokesd_client: @@spokesd_client)
        else
          ::GitRPC.new(url)
        end
      end

      def self.gitrpc_send_multiple(urls, message, args, kwargs, options = {})
        if !GitHub.enterprise? && urls.any? { |url| url.start_with?("bertrpc:") }
          @@spokesd_client ||= GitHub::Spokes::Client::Spokesd.instance
          options[:spokesd_client] = @@spokesd_client
        end

        GitRPC.send_multiple(urls, message, args, kwargs, options)
      end

      # A FlipperActor that can be used on a network ID, without having to
      # load the RepositoryNetwork.
      class NetworkIdActor
        include GitHub::FlipperActor
        include GitHub::VexiActor

        def initialize(network_id)
          @network_id = network_id
        end

        def flipper_id
          "RepositoryNetwork:#{@network_id}"
        end

        def vexi_id
          flipper_id
        end
      end
    end
  end
end
