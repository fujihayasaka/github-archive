# typed: true
# frozen_string_literal: true

module GitHub
  class DGit
    class ColdStorage

      def self.set_network_storage_state(network_id, state)
        db = GitHub::DGit::DB.for_network_id(network_id)
        sql = db.SQL.new \
          network_id: network_id,
          state: state
        sql.add <<-SQL
          INSERT INTO cold_networks (network_id, state, created_at, updated_at)
            VALUES (:network_id, :state, NOW(), NOW())
          ON DUPLICATE KEY UPDATE
            state = VALUES(state),
            updated_at = VALUES(updated_at)
        SQL
        db.throttle { sql.run }
        sql.affected_rows == 1 || is_network_cold?(network_id)
      end

      def self.mark_network_cold(network_id)
        self.set_network_storage_state(network_id, 1)
      end

      def self.mark_network_never_cold(network_id)
        self.set_network_storage_state(network_id, 2)
      end

      def self.mark_network_not_cold(network_id)
        db = GitHub::DGit::DB.for_network_id(network_id)
        sql = db.SQL.new \
          network_id: network_id,
          state: 0
        sql.add <<-SQL
          UPDATE cold_networks SET
            state=:state,
            updated_at=NOW()
          WHERE network_id=:network_id
        SQL
        db.throttle { sql.run }
        sql.affected_rows == 1
      end

      # Unlike other methods, this takes a db so that the change can be included
      # in a single db transaction.  Similarly, we don't try to throttle the change.
      def self.remove_network_state(db, network_id)
        sql = db.SQL.new \
          network_id: network_id
        sql.add <<-SQL
          DELETE FROM cold_networks
          WHERE network_id=:network_id
        SQL
        sql.run
        sql.affected_rows == 1
      end

      def self.is_network_cold?(network_id)
        db = GitHub::DGit::DB.for_network_id(network_id)
        sql = db.SQL.new \
          network_id: network_id
        sql.add <<-SQL
          SELECT 1 FROM cold_networks
          WHERE network_id=:network_id
          AND state=1
        SQL
        sql.run.results.size > 0
      end

      def self.is_network_read_heavy?(network_id)
        db = GitHub::DGit::DB.for_network_id(network_id)
        sql = db.SQL.new \
          network_id: network_id
        sql.add <<-SQL
          SELECT 1 FROM cold_networks
          WHERE network_id=:network_id
          AND state=4
        SQL
        sql.run.results.size > 0
      end

      def self.cold_network_times(network_id)
        db = GitHub::DGit::DB.for_network_id(network_id)
        sql = db.SQL.new \
          network_id: network_id
        sql.add <<-SQL
          SELECT created_at, updated_at FROM cold_networks
          WHERE network_id=:network_id
        SQL
        if sql.results.size != 1
          nil
        else
          sql.results[0]
        end
      end

      # Working out how many entries are in the cold network table is likely to be
      # expensive once it starts to get used.  This is a convenient and cheap
      # alternative to counting the rows.  It ignores cold networks that have been
      # subsequently warmed, and networks that have been deleted.  Both of these
      # are expected to be relatively small, so this number is a pretty good guess.
      def self.approximate_count
        sql = GitHub::DGit::SpokesSQL.run <<-SQL
          SELECT auto_increment
          FROM information_schema.tables
          WHERE table_name='cold_networks'
        SQL
        if sql.results.size != 1
          nil
        else
          sql.results[0][0]
        end
      end
    end
  end
end
