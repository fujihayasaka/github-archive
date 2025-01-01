# typed: false
# frozen_string_literal: true

require "github/config/mysql"
require "github/dgit"

module GitHub
  class DGit
    module Routing
      REPO_KEYS = {
        repo_id: 0,
        network_id: 1,
        root_id: 2,
        is_wiki: 3,
      }

      module_function

      def gist_id(repo_name)
        id, repo_name = lookup_gist_by_reponame(repo_name)
        id
      end

      def repo_id(owner, name)
        lookup_repo(owner, name)[REPO_KEYS[:repo_id]]
      end

      def repo_path(owner, name)
        is_wiki = name.end_with?(".wiki")
        name = name.chomp(".wiki") if is_wiki

        lookup = lookup_repo(owner, name)
        network_id = lookup[REPO_KEYS[:network_id]]
        repo_id = lookup[REPO_KEYS[:repo_id]]

        path = nw_storage_path(network_id: network_id)
        "#{path}/#{repo_id}#{is_wiki ? ".wiki" : ""}.git"
      end

      def network_path(network_id)
        path = nw_storage_path(network_id: network_id)
        "#{path}/network.git"
      end

      def hosts_for_nwo(owner, name)
        lookup = lookup_repo("#{owner}/#{name}")
        repo_id = lookup[REPO_KEYS[:repo_id]]
        is_wiki = lookup[REPO_KEYS[:is_wiki]]
        hosts_for_repo(repo_id, is_wiki)
      end

      def hosts_for_repo(repo_id, wiki = false)
        all_repo_replicas(repo_id, wiki).select(&:healthy?).map(&:host)
      end

      def hosts_for_network(network_id)
        all_network_replicas(network_id).select(&:healthy?).map(&:host)
      end

      # Returns only *healthy* gist replica hosts: current checksum
      # values match the repository_checksums record.
      def hosts_for_gist(gist_id)
        all_gist_replicas(gist_id).select(&:healthy?).map(&:host)
      end

      # Returns set of healthy hosts for exporting the given repo type.
      def hosts_for_repo_type_export(repo_type, id)
        case repo_type
        when GitHub::DGit::RepoType::REPO
          hosts_for_network(id)
        when GitHub::DGit::RepoType::GIST
          hosts_for_gist(id)
        else
          desc = GitHub::DGit::RepoType::REPO_TYPES[repo_type]
          raise StandardError, "unhandled repo_type: #{repo_type} #{desc}"
        end
      end

      def all_hosts_for_network(network_id)
        all_network_replicas(network_id).map(&:host)
      end

      def all_hosts_for_gist(gist_id)
        all_gist_replicas(gist_id).map(&:host)
      end

      def preferred_reader_for_repo(repo_id)
        hosts_for_repo(repo_id).first
      end

      def preferred_reader_for_network(network_id)
        hosts_for_network(network_id).first
      end

      def with_master_db_retry
        results = yield
        return results unless results.empty? && !ActiveRecord::Base.connected_to?(role: :writing)

        # Retry queries against the primary database
        # for the case that no replicas were found,
        # which can happen due to replica lag.
        GitHub.dogstats.increment("spokes.with_master_db_retry.attempt")
        ActiveRecord::Base.connected_to(role: :writing, prevent_writes: true) do
          results = yield
        end
        GitHub.dogstats.increment("spokes.with_master_db_retry.success") unless results.empty?
        results
      end

      def repo_checksum(network_id, repo_id)
        GitHub::DGit::DB.for_network_id(network_id).SQL.values(
          "SELECT checksum FROM repository_checksums WHERE repository_id = :repo_id AND repository_type = :t",
          network_id: network_id, repo_id: repo_id, t: GitHub::DGit::RepoType::REPO).first
      end

      def wiki_checksum(network_id, repo_id)
        GitHub::DGit::DB.for_network_id(network_id).SQL.values(
          "SELECT checksum FROM repository_checksums WHERE repository_id = :repo_id AND repository_type = :t",
          network_id: network_id, repo_id: repo_id, t: GitHub::DGit::RepoType::WIKI).first
      end

      def full_checksum_for_db(repo_id, repo_type, db)
        hr = db.SQL.hash_results(
               "SELECT checksum, created_at, updated_at FROM repository_checksums WHERE repository_id = :repo_id AND repository_type = :t",
               repo_id: repo_id, t: repo_type).first
        if hr.nil? || hr.empty?
          [nil, nil, nil, nil, nil]
        else
          [repo_id, repo_type, hr["checksum"], hr["created_at"], hr["updated_at"]]
        end
      end

      def full_repo_checksum_for_db(repo_id, db)
        full_checksum_for_db(repo_id, GitHub::DGit::RepoType::REPO, db)
      end

      def full_wiki_checksum_for_db(repo_id, db)
        full_checksum_for_db(repo_id, GitHub::DGit::RepoType::WIKI, db)
      end

      def repo_replica_for_host(repo_id, host)
        all_repo_replicas(repo_id).find { |rr| rr.fileserver.name == host }
      end

      def wiki_replica_for_host(repo_id, host)
        all_repo_replicas(repo_id, true).find { |rr| rr.fileserver.name == host }
      end

      # Returns an array of replicas, whether or not they are healthy.
      # They will be sorted by the order of read preference -- try the
      # first one first, the second one second, and so on.
      #
      # Each element in the array is a GitHub::DGit::Replica::Repo.
      def all_repo_replicas(repo_id, wiki = false)
        repo_type = wiki ? GitHub::DGit::RepoType::WIKI : GitHub::DGit::RepoType::REPO

        # First map repo ID -> network ID.
        network_id = GitHub::DGit::Maintenance.network_source_id_for(repo_id)
        return [] unless network_id

        GitHub::Spokes.client.all_replicas(network_id, repo_id, repo_type)
      end

      def all_repo_replicas_in_db(network_id, repo_id, repo_type, db)
        # Get all healthy replicas.
        sql_results = with_master_db_retry do
          sql = db.SQL.new \
            repo_id: repo_id, network_id: network_id, repository_type: repo_type
          sql.add <<-SQL
            SELECT nr.host, nr.read_weight, fs.quiescing, fs.online, nr.state, rr.checksum, rc.checksum as expected_checksum, fs.evacuating, fs.datacenter, fs.rack, fs.embargoed, fs.ip, fs.non_voting, fs.hdd_storage, rr.created_at, rr.updated_at, rr.network_replica_id, fs.fqdn, #{GitHub::DGit.have_cache_location_column? ? "fs.cache_location" : "NULL" }
              FROM network_replicas nr
              JOIN repository_replicas rr ON rr.repository_id=:repo_id AND rr.repository_type=:repository_type AND nr.host=rr.host
              LEFT JOIN repository_checksums rc ON rc.repository_id=:repo_id AND rc.repository_type=:repository_type
              JOIN fileservers fs ON nr.host=fs.host
              WHERE nr.network_id=:network_id
          SQL
          sql.results
        end

        sort_replicas(sql_results.map do |row|
          fileserver = Fileserver.new \
            name: row[0],
            ip: row[11],
            fqdn: row[17],
            evacuating: row[7] == 1,
            datacenter: row[8] || GitHub.default_datacenter,
            rack: row[9] || GitHub.default_rack,
            online: row[3] == 1,
            embargoed: row[10] == 1,
            voting: row[12] != 1,
            hdd_storage: row[13] == 1,
            cache_location: row[18]
          Replica::Repo.new \
            db_name: db.name,
            fileserver: fileserver,
            read_weight: row[1],
            quiescing: row[2] == 1,
            state: row[4],
            checksum: row[5],
            expected_checksum: row[6],
            created_at: row[14],
            updated_at: row[15],
            db_network_replica_id: row[16]
        end)
      end

      def read_weight_factor(read_weight)
        # If multiple routes have non-zero read-weights, then do a
        # weighted random shuffle.  We do that by assigning each
        # read-weight with an exponentially-distributed random value and
        # then sorting by the result.  That's the simplest, O(n) way to
        # map from a set of weights to an order predicted by the weights.
        # For example, if server A has twice the weight of server B, then
        # A appears ahead of B twice as often in the result.  If server A
        # has a quarter of the total weight, it will appear first a
        # quarter of the time.
        #
        # Cribbed from:
        # http://programmers.stackexchange.com/questions/233541/how-to-implement-a-weighted-shuffle
        # http://stackoverflow.com/questions/2106503/pseudorandom-number-generator-exponential-distribution
        return -100 if read_weight <= 0

        # This changes the read weight from an integer between 1 and
        # 100 to a float that's less than 0.0. Practically speaking,
        # the smallest this gets is around -11.
        Math.log(1 - rand) / read_weight
      end

      def sort_replicas(replicas)
        preferred_dc = GitHub.datacenter
        replicas.sort_by do |replica|
          [
            GitHub::DGit.local_access?(replica.host) ? 0 : 1,
            replica.quiescing? ? 1 : 0,
            replica.in_region?(dc: preferred_dc) ? 0 : 1,
            replica.hdd_storage? ? 1 : 0,
            replica.in_datacenter?(dc: preferred_dc) ? 0 : 1,
            # Random factor that favors otherwise-equivalent hosts
            # proportional to their read weights:
            -read_weight_factor(replica.read_weight),
            # Finally, sort by host, to give determinism among
            # zero-weight hosts:
            replica.host,
          ]
        end
      end

      def network_replica_for_host(network_id, host)
        all_network_replicas(network_id).find { |nr| nr.fileserver.name == host }
      end

      def all_network_replicas(network_id)
        raise ArgumentError, "network id is a #{network_id.class}, not a Integer" if !network_id.is_a?(Integer)
        results = GitHub::Spokes.client.all_replicas(network_id, nil, GitHub::DGit::RepoType::NETWORK)
        if results.empty?
          GitHub.logger.info("no network replicas were returned", "gh.repo.network_id" => network_id)
        end
        results
      end

      def all_network_replicas_for_many(network_ids)
        results = Hash[network_ids.map { |id| [id, []] }]

        GitHub::DGit::DB.each_for_network_ids(network_ids) do |db, network_ids|
          db_result = all_network_replicas_for_many_in_db(network_ids, db)
          db_result.each do |id, nrs|
            next if nrs.empty?
            results[id] += nrs
          end
        end

        results.each_key do |key|
          results[key] = sort_replicas(results[key])
        end

        results
      end

      def all_network_replicas_for_many_in_db(network_ids, db)
        results = Hash[network_ids.map { |id| [id, []] }]
        return results if network_ids.empty?

        sql_results = with_master_db_retry do
          db.SQL.results(<<-SQL, network_ids: network_ids)
            SELECT nr.network_id, nr.host, nr.read_weight, fs.quiescing, fs.online, nr.state, fs.evacuating, fs.datacenter, fs.rack, fs.embargoed, fs.ip, fs.non_voting, fs.hdd_storage, nr.created_at, nr.updated_at, nr.id, fs.fqdn, #{GitHub::DGit.have_cache_location_column? ? "fs.cache_location" : "NULL" }
              FROM network_replicas nr
              JOIN fileservers fs ON nr.host=fs.host
              WHERE nr.network_id IN :network_ids
          SQL
        end

        sql_results.each do |row|
          network_id = row[0]
          fileserver = Fileserver.new \
            name: row[1],
            ip: row[10],
            fqdn: row[16],
            evacuating: row[6] == 1,
            datacenter: row[7] || GitHub.default_datacenter,
            rack: row[8] || GitHub.default_rack,
            online: row[4] == 1,
            embargoed: row[9] == 1,
            voting: row[11] != 1,
            hdd_storage: row[12] == 1,
            cache_location: row[17]
          replica = Replica::Network.new \
            db_name: db.name,
            fileserver: fileserver,
            read_weight: row[2],
            quiescing: row[3] == 1,
            state: row[5],
            created_at: row[13],
            updated_at: row[14],
            db_network_replica_id: row[15]
          results[network_id] << replica
        end

        results
      end

      def gist_checksum(gist_id)
        GitHub::DGit::DB.for_gist_id(gist_id).SQL.values(
          "SELECT checksum FROM repository_checksums WHERE repository_id = :gist_id AND repository_type = :t",
          gist_id: gist_id, t: GitHub::DGit::RepoType::GIST).first
      end

      def full_gist_checksum_for_db(gist_id, db)
        full_checksum_for_db(gist_id, GitHub::DGit::RepoType::GIST, db)
      end

      def gist_replica_for_host(gist_id, host)
        all_gist_replicas(gist_id).find { |gr| gr.fileserver.name == host }
      end

      def all_gist_replicas(gist_id)
        raise ArgumentError, "invalid gist id" if !gist_id.is_a?(Integer)
        GitHub::Spokes.client.all_replicas(nil, gist_id, GitHub::DGit::RepoType::GIST)
      end

      def all_gist_replicas_for_many(gist_ids)
        results = Hash[gist_ids.map { |id| [id, []] }]

        GitHub::DGit::DB.each_for_gist_ids(gist_ids) do |db, gist_id_slice|
          db_result = all_gist_replicas_for_many_in_db(gist_id_slice, db)
          db_result.each do |id, grs|
            next if grs.empty?
            results[id] += grs
          end
        end

        results.each_key do |key|
          results[key] = sort_replicas(results[key])
        end

        results
      end

      def all_gist_replicas_for_many_in_db(gist_ids, db)
        results = Hash[gist_ids.map { |id| [id, []] }]
        return results if gist_ids.empty?

        sql_results = with_master_db_retry do
          db.SQL.results(<<-SQL, gist_ids: gist_ids, repo_type: GitHub::DGit::RepoType::GIST)
            SELECT gr.gist_id, gr.host, gr.read_weight, fs.quiescing, fs.online, gr.state, gr.checksum, rc.checksum as expected_checksum, fs.evacuating, fs.datacenter, fs.rack, fs.embargoed, fs.ip, fs.non_voting, fs.hdd_storage, gr.created_at, gr.updated_at, fs.fqdn, #{GitHub::DGit.have_cache_location_column? ? "fs.cache_location" : "NULL" }
              FROM gist_replicas gr
              LEFT JOIN repository_checksums rc ON rc.repository_id=gr.gist_id AND rc.repository_type=:repo_type
              JOIN fileservers fs ON gr.host=fs.host
              WHERE gr.gist_id IN :gist_ids
          SQL
        end

        sql_results.each do |row|
          gist_id = row[0]
          fileserver = Fileserver.new \
            name: row[1],
            ip: row[12],
            fqdn: row[17],
            evacuating: row[8] == 1,
            datacenter: row[9] || GitHub.default_datacenter,
            rack: row[10] || GitHub.default_rack,
            online: row[4] == 1,
            embargoed: row[11] == 1,
            voting: row[13] != 1,
            hdd_storage: row[14] == 1,
            cache_location: row[18]
          replica = Replica::Gist.new \
            db_name: db.name,
            fileserver: fileserver,
            read_weight: row[2],
            quiescing: row[3] == 1,
            state: row[5],
            checksum: row[6],
            expected_checksum: row[7],
            created_at: row[15],
            updated_at: row[16]
          results[gist_id] << replica
        end

        results
      end

      # Look up an nwo.
      # Returns:
      #   [ repo_id, network_id, root_id, partition, is_wiki ]
      # Not at all specific to dgit.
      def lookup_repo(owner, name = nil)
        if name.nil?
          orig_owner = owner
          owner, name, junk = orig_owner.split("/")
          unless owner && name && !junk
            raise ::GitHub::DGit::RepoNotFound,
                  "Invalid format. Try owner/repo format."
          end
        end

        is_wiki = name.end_with?(".wiki")
        name = name.chomp(".wiki") if is_wiki

        sql = Arel.sql(<<-SQL, login: owner)
          SELECT id FROM users
          WHERE login = :login
        SQL
        owner_id = ApplicationRecord::Domain::Users.connection.select_rows(sql).first

        # look up the repo
        sql = Arel.sql <<-SQL
          SELECT repositories.id as repo_id,
                 repository_networks.id as network_id,
                 repository_networks.root_id
          FROM repository_networks
          INNER JOIN repositories
            ON repositories.source_id = repository_networks.id
        SQL
        sql += Arel.sql <<-SQL, owner_id: owner_id, name: name
          WHERE repositories.owner_id = :owner_id
            AND repositories.name = :name
            AND repositories.active = 1
        SQL
        result = ApplicationRecord::Domain::Repositories.connection.select_rows(sql).first
        repo = result

        raise ::GitHub::DGit::RepoNotFound if repo.nil?
        repo + [is_wiki]
      end

      def lookup_gist(nwo)
        orig_nwo = nwo
        owner, name, junk = orig_nwo.split("/")
        unless owner && name && !junk
          raise ::GitHub::DGit::RepoNotFound,
                "Invalid format. Try owner/repo format."
        end

        #
        # This function duplicates what Gist.with_name_with_owner
        # does, but without needing to drag in any of the Gist model
        # Rails dependencies.
        #

        if owner != "anonymous"
          sql = Arel.sql(<<-SQL, login: owner)
            SELECT id FROM users
            WHERE login = :login
          SQL
          user_id = ApplicationRecord::Domain::Users.connection.select_value(sql)

          sql = Arel.sql(<<-SQL, user_id: user_id, repo_name: name)
            SELECT id, repo_name FROM gists
            WHERE user_id = :user_id
              AND repo_name = :repo_name
          SQL
          gist = ApplicationRecord::Domain::Gists.connection.select_rows(sql).first
        else
          sql = Arel.sql(<<-SQL, repo_name: name)
            SELECT id, repo_name FROM gists
            WHERE repo_name = :repo_name
          SQL
          gist = ApplicationRecord::Domain::Gists.connection.select_rows(sql).first
        end

        raise ::GitHub::DGit::RepoNotFound if gist.nil?
        gist
      end

      def lookup_gist_by_reponame(name)
        lookup_gist("anonymous/#{name}")
      end

      # Include this module (after GitHub::DGit::Routing) if you
      # want to be able to look up gists as "anonymous/<name>" and
      # "anonymous/<id>".
      #
      # This is used in some of script/dgit-*.
      module GistById
        def lookup_gist(nwo)
          super
        rescue GitHub::DGit::RepoNotFound => e
          if nwo =~ /\Aanonymous\/(\d+)\z/
            gist = ApplicationRecord::Domain::Gists.connection.select_rows(Arel.sql("SELECT id, repo_name FROM gists WHERE id = :id", id: $1)).first
            raise e unless gist
          end
          gist
        end
      end
    end
  end
end
