# typed: false
# frozen_string_literal: true

require "github/config/mysql"
require "github/dgit"
require "application_record"

module GitHub
  class DGit
    class Enterprise
      MAX_SQL_ROWS = 100

      # Returns network paths and hosts for all repos and gists with maximum read_weight.
      def self.all_network_paths_with_max_read_weight
        raise "enterprise-only method unexpectedly invoked (#{__method__})" unless GitHub.enterprise?

        networks = {}
        gists = {}

        sql = Arel.sql <<-SQL
          SELECT rn2.id, nr2.host FROM
          (  SELECT DISTINCT rn1.id,  MAX(nr1.read_weight) as max_weight
             FROM repository_networks rn1
             JOIN network_replicas nr1 on nr1.network_id = rn1.id
             INNER JOIN fileservers f1 on f1.host = nr1.host
             WHERE nr1.state = 1 AND f1.online = 1
             GROUP BY rn1.id
          ) as x
          INNER JOIN repository_networks rn2 on rn2.id = x.id
          INNER JOIN network_replicas nr2 on nr2.network_id = rn2.id
          INNER JOIN fileservers f2 on f2.host = nr2.host
          WHERE nr2.read_weight = x.max_weight AND nr2.state = 1 AND f2.online = 1
          /* cross-schema-domain-query-exempted */
        SQL

        ApplicationRecord::Domain::Repositories.connection.select_rows(sql).each do |r|
          networks[r[0]] = "#{GitHub::Routing.nw_storage_path(network_id: r[0])} #{r[1]}"
        end

        sql = Arel.sql <<-SQL
          SELECT g2.id, gr2.host, g2.repo_name FROM
          ( SELECT DISTINCT gr.gist_id, NULL, gr.host, g.repo_name, MAX(gr.read_weight) as max_weight
            FROM gist_replicas gr
            INNER JOIN gists g on g.id = gr.gist_id
            INNER JOIN fileservers f1 ON f1.host = gr.host
            WHERE gr.state = 1 AND f1.online = 1
            GROUP BY gr.gist_id
          ) as y
          INNER JOIN gist_replicas gr2 on gr2.gist_id = y.gist_id
          INNER JOIN gists g2 on g2.id = gr2.gist_id
          INNER JOIN fileservers f2 ON f2.host = gr2.host
          WHERE gr2.read_weight = y.max_weight AND gr2.state = 1 AND f2.online = 1
          /* cross-schema-domain-query-exempted */
        SQL

        ApplicationRecord::Domain::Gists.connection.select_rows(sql).each do |r|
          gists[r[0]] = "#{Pathname(GitHub::Routing.gist_storage_path(repo_name: r[2]))} #{r[1]}"
        end

        networks.values + gists.values
      end

      def self.remove_archived_repo_replica_routes(network_id, repo_type)
        raise "enterprise-only method unexpectedly invoked (#{__method__})" unless GitHub.enterprise?
        raise ArgumentError, "invalid network id" if !network_id.is_a?(Integer)
      end

      # Remove all replica routes for the given repo network or gist.
      def self.remove_replica_routes(repo_type, id)
        case repo_type
        # normal repositories and wikis are only ever migrated
        # together, so they are both handled by the REPO case
        when GitHub::DGit::RepoType::REPO
          remove_repo_replica_routes(id)
        when GitHub::DGit::RepoType::GIST
          remove_gist_replica_routes(id)
        else
          desc = GitHub::DGit::RepoType::REPO_TYPES[repo_type]
          raise StandardError, "unhandled repo_type: #{repo_type} #{desc}"
        end
      end

      def self.delete_checksums_for_network(network_id)
        db = GitHub::DGit::DB.for_network_id(network_id)
        GitHub::DGit::Util.repo_ids_for(network_id).each_slice(MAX_SQL_ROWS) do |some|
          ActiveRecord::Base.connected_to(role: :writing) do
            db.throttle do
              sql = db.SQL.new \
                             network_id: network_id,
              types: GitHub::DGit::RepoType::REPO_ISH,
              ids: some
              sql.run <<-SQL
                DELETE FROM repository_checksums
                  WHERE repository_checksums.repository_id IN :ids
                    AND repository_checksums.repository_type IN :types
              SQL
              $stderr.puts "Deleted #{sql.affected_rows} from repository_checksums" unless GitHub.enterprise?
            end
          end
        end
      end

      # Remove all replica routes for a given repo network.
      def self.remove_repo_replica_routes(network_id)
        db = GitHub::DGit::DB.for_network_id(network_id)

        ActiveRecord::Base.connected_to(role: :writing) do
          db.SQL.run("DELETE FROM network_replicas WHERE network_id = :network_id",
                     network_id: network_id)
        end # connected_to

        GitHub::DGit::Util.repo_ids_for(network_id).each_slice(MAX_SQL_ROWS) do |some|
          ActiveRecord::Base.connected_to(role: :writing) do
            db.throttle do
              sql = db.SQL.new \
                network_id: network_id,
                types: GitHub::DGit::RepoType::REPO_ISH,
                ids: some
              sql.run <<-SQL
                DELETE FROM repository_replicas
                  WHERE repository_replicas.repository_id IN :ids
                    AND repository_replicas.repository_type IN :types
              SQL
              $stderr.puts "Deleted #{sql.affected_rows} from repository_replicas" unless GitHub.enterprise?
            end # db.throttle
          end # connected_to
        end # each_slice

        delete_checksums_for_network(network_id)
      end

      # Remove all replica routes for a given gist.
      def self.remove_gist_replica_routes(gist_id)
        ActiveRecord::Base.connected_to(role: :writing) do
          gist_db = GitHub::DGit::DB.for_gist_id(gist_id)
          gist_db.SQL.run("DELETE FROM gist_replicas WHERE gist_id = :gist_id",
                          gist_id: gist_id)
          gist_db.SQL.run(<<-SQL, gist_id: gist_id, repo_type: GitHub::DGit::RepoType::GIST)
            DELETE repository_checksums FROM repository_checksums
              WHERE repository_checksums.repository_id=:gist_id
                AND repository_checksums.repository_type=:repo_type
          SQL
        end
      end

      def self.add_replica_routes(logger, repo_type, id, hosts, checksums, update_existing = false)
        case repo_type
        # normal repositories and wikis are only ever migrated
        # together, so they are both handled by the REPO case
        when GitHub::DGit::RepoType::REPO
          add_repo_replica_routes(logger, id, hosts,
                                  checksums[GitHub::DGit::RepoType::REPO],
                                  checksums[GitHub::DGit::RepoType::WIKI],
                                  update_existing)
        when GitHub::DGit::RepoType::GIST
          add_gist_replica_routes(logger, id, hosts,
                                  checksums[GitHub::DGit::RepoType::GIST],
                                  update_existing)
        else
          desc = GitHub::DGit::RepoType::REPO_TYPES[repo_type]
          raise StandardError, "unhandled repo_type: #{repo_type} #{desc}"
        end
      end

      # Insert the given set of repository_checksums records.  If update_existing
      # is true, an insert that would result in a duplicate key update will only
      # update the checksum and updated_at values.
      #
      #  - network_id:       network ID for the given repositories
      #  - rows:             list of [repository_id, repository_type, checksum,
      #                      created_at, updated_at] tuples suitable for GitHub::SQL
      #  - update_existing:  set to update checksum and updated_at upon duplicate key
      def self.insert_repository_checksums(network_id, rows, update_existing = false)
        # + keeps the string from being frozen
        query = +<<-SQL
          INSERT INTO repository_checksums
            (repository_id, repository_type, checksum, created_at, updated_at)
          VALUES :rows
        SQL

        if update_existing
          query << <<-SQL
            ON DUPLICATE KEY UPDATE
              updated_at = VALUES(updated_at),
              checksum   = VALUES(checksum)
          SQL
        end

        db = GitHub::DGit::DB.for_network_id(network_id)
        ActiveRecord::Base.connected_to(role: :writing) do
          rows.each_slice(MAX_SQL_ROWS) do |some|
            db.throttle do
              sql = db.SQL.new query, network_id: network_id, rows: GitHub::SQL::ROWS(some)
              sql.run
              $stderr.puts "Added #{sql.affected_rows} to repository_checksums" unless GitHub.enterprise?
            end # throttle
          end # each_slice
        end # connected_to
      end

      def self.insert_gist_checksums(gist_id, rows, update_existing = false)
        # + keeps the string from being frozen
        query = +<<-SQL
          INSERT INTO repository_checksums
            (repository_id, repository_type, checksum, created_at, updated_at)
          VALUES :rows
        SQL

        if update_existing
          query << <<-SQL
            ON DUPLICATE KEY UPDATE
              updated_at = VALUES(updated_at),
              checksum   = VALUES(checksum)
          SQL
        end

        db = GitHub::DGit::DB.for_gist_id(gist_id)
        ActiveRecord::Base.connected_to(role: :writing) do
          rows.each_slice(MAX_SQL_ROWS) do |some|
            db.throttle do
              sql = db.SQL.new query, gist_id: gist_id, rows: GitHub::SQL::ROWS(some)
              sql.run
              $stderr.puts "Added #{sql.affected_rows} to repository_checksums" unless GitHub.enterprise?
            end # throttle
          end # each_slice
        end # connected_to
      end

      # Add entries for a repo network to all three DGit tables:
      # network_replicas, repository_replicas, and repository_checksums.
      #  - logger:      any Logger object
      #  - network_id:  the network to route in DGit
      #  - hosts:            an array of hosts (as strings) where the network
      #                      will live
      #  - repo_checksums:   a hash mapping {repo_id => checksum} for all repo
      #                      forks in the network
      #  - wiki_checksums:   a hash mapping {repo_id => checksum} for all wiki
      #                      forks in the network
      # Note that the SQL tables have a separate checksum entry for each
      # replica -- i.e., <repo_id,host> tuple -- even though the
      # `checksums` has only one entry for each repo_id.  That's because
      # we wouldn't have gotten here unless the hosts agreed on the
      # checksum for each fork.
      def self.add_repo_replica_routes(logger, network_id, hosts, repo_checksums, wiki_checksums, update_existing = false)
        weights = GitHub::DGit.alloc_read_weight(hosts)
        logger.info "adding network route to #{hosts.inspect} with weights=#{weights.inspect}"
        hosts.map do |host|
          rows = [[network_id, host, GitHub::DGit::ACTIVE, weights[host],
             GitHub::SQL::NOW, GitHub::SQL::NOW]]

          # + keeps the string from being frozen
          query = +<<-SQL
            INSERT INTO network_replicas
              (network_id, host, state, read_weight, created_at, updated_at)
            VALUES :rows
          SQL

          if update_existing
            query << <<-SQL
            ON DUPLICATE KEY UPDATE
              updated_at = VALUES(updated_at),
              state      = VALUES(state)
            SQL
          end

          db = GitHub::DGit::DB.for_network_id(network_id)

          network_replica_id = ActiveRecord::Base.connected_to(role: :writing) do
            sql = db.SQL.new query, network_id: network_id, rows: GitHub::SQL::ROWS(rows)
            sql.run
            sql.last_insert_id
          end

          nri_query = <<-SQL
            SELECT id FROM network_replicas WHERE network_id=:network_id AND host=:host
          SQL

          # Get the id for whichever network_replica we just inserted or modified
          network_replica_id = ActiveRecord::Base.connected_to(role: :reading) do
            sql = db.SQL.new nri_query, network_id: network_id, host: host
            sql.results[0][0]
          end

          num_forks = repo_checksums.keys.length
          logger.info "adding repo route for #{num_forks} fork(s) to #{hosts.inspect}"
          rows = []
          repo_checksums.each do |repo_id, checksum|
            rows << [repo_id, GitHub::DGit::RepoType::REPO, network_replica_id, host, checksum, GitHub::SQL::NOW, GitHub::SQL::NOW]
          end

          # only add wiki replicas where the wiki exists on disk (non-nil checksum)
          wiki_checksums = wiki_checksums.select { |_repo_id, checksum| !checksum.nil? }
          wiki_checksums.each do |repo_id, checksum|
            rows << [repo_id, GitHub::DGit::RepoType::WIKI, network_replica_id, host, checksum, GitHub::SQL::NOW, GitHub::SQL::NOW]
          end

          # + keeps the string from being frozen
          query = +<<-SQL
            INSERT INTO repository_replicas
              (repository_id, repository_type, network_replica_id, host, checksum, created_at, updated_at)
            VALUES :rows
          SQL

          if update_existing
            query << <<-SQL
              ON DUPLICATE KEY UPDATE
                updated_at = VALUES(updated_at),
                checksum   = VALUES(checksum),
                network_replica_id = VALUES(network_replica_id)
            SQL
          end

          rows.each_slice(MAX_SQL_ROWS) do |some|
            ActiveRecord::Base.connected_to(role: :writing) do
              db.throttle do
                sql = db.SQL.new query, network_id: network_id, rows: GitHub::SQL::ROWS(some)
                sql.run
                $stderr.puts "Added #{sql.affected_rows} to repository_replicas" unless GitHub.enterprise?
              end
            end
          end
        end

        rows = repo_checksums.map do |repo_id, checksum|
          [repo_id, GitHub::DGit::RepoType::REPO, checksum, GitHub::SQL::NOW, GitHub::SQL::NOW]
        end

        wiki_checksums.each do |repo_id, checksum|
          rows << [repo_id, GitHub::DGit::RepoType::WIKI, checksum, GitHub::SQL::NOW, GitHub::SQL::NOW]
        end

        insert_repository_checksums(network_id, rows, update_existing)
      end

      # Add entries for a gist to its DGit tables:
      # gist_replicas, and repository_checksums.
      #  - logger:      any Logger object
      #  - gist_id:     the gist to route in DGit
      #  - hosts:           an array of hosts (as strings) where the gist
      #                     will live
      #  - gist_checksum:   a string checksum for the gist
      def self.add_gist_replica_routes(logger, gist_id, hosts, gist_checksum, update_existing = false)
        weights = GitHub::DGit.alloc_read_weight(hosts)
        logger.info "adding gist route to #{hosts.inspect} with weights=#{weights.inspect}"
        rows = hosts.map do |host|
          [gist_id, host, gist_checksum, GitHub::DGit::ACTIVE, weights[host],
            GitHub::SQL::NOW, GitHub::SQL::NOW]
        end

        # + keeps the string from being frozen
        query = +<<-SQL
          INSERT INTO gist_replicas
            (gist_id, host, checksum, state, read_weight, created_at, updated_at)
          VALUES :rows
        SQL

        if update_existing
          query << <<-SQL
          ON DUPLICATE KEY UPDATE
            updated_at = VALUES(updated_at),
            state      = VALUES(state)
          SQL
        end

        ActiveRecord::Base.connected_to(role: :writing) do
          GitHub::DGit::DB.for_gist_id(gist_id).SQL.run query, rows: GitHub::SQL::ROWS(rows), gist_id: gist_id
        end
        rows = [
         [gist_id, GitHub::DGit::RepoType::GIST, gist_checksum, GitHub::SQL::NOW, GitHub::SQL::NOW],
        ]

        insert_gist_checksums(gist_id, rows, update_existing)
      end
    end # Enterprise
  end #DGit
end # GitHub
