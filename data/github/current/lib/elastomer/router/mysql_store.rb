# typed: true
# frozen_string_literal: true

module Elastomer
  class Router
    class MysqlStore
      include Enumerable

      TABLE_NAME = :elastomer_index_memos

      # Retrieve an IndexConfig from the MySQL table.
      #
      # name - The name of the search index
      #
      # Returns the IndexConfig for the search index or `nil` if the named search
      # index does not exist in the table.
      def get_config(name)
        query = Arel.sql(<<-SQL, name: name, datacenter: datacenter)
          SELECT * FROM #{TABLE_NAME}
          WHERE name = :name
          AND datacenter = :datacenter
        SQL

        rows = ElastomerIndexMemo.connection.select_all(query)
        hydrate_config(rows.first)
      end

      # Delete the named IndexConfig from the MySQL table.
      #
      # config - The IndexConfig to delete
      def delete_config(name)
        query = Arel.sql(<<-SQL, name: name, datacenter: datacenter)
          DELETE FROM #{TABLE_NAME}
          WHERE name = :name
          AND datacenter = :datacenter
        SQL
        ActiveRecord::Base.connected_to(role: :writing) do
          ElastomerIndexMemo.connection.delete(query)
        end
      end

      # Store an IndexConfig in the MySQL table.
      #
      # config - The IndexConfig to store
      #
      # Returns the config
      def put_config(config)
        opts = {
          name: config.name,
          cluster: config.cluster,
          version: config.version,
          read: config.read,
          write: config.write,
          primary: config.primary,
          read_pct: config.read_pct,
        }
        opts[:created_at] = opts[:updated_at] = Time.now

        opts[:version] = nil if config.version.nil?
        opts[:datacenter] = datacenter

        # rubocop:disable GitHub/InsertOnDuplicateKeyUpdate
        query = Arel.sql(<<-SQL, **opts)
          INSERT INTO #{TABLE_NAME} (`name`,`datacenter`,`cluster`,`version`,`read`,`write`,`primary`,`read_pct`,`created_at`,`updated_at`)
          VALUES (:name,:datacenter,:cluster,:version,:read,:write,:primary,:read_pct,:created_at,:updated_at)
          ON DUPLICATE KEY UPDATE
            `cluster`    = :cluster,
            `datacenter` = :datacenter,
            `version`    = :version,
            `read`       = :read,
            `write`      = :write,
            `primary`    = :primary,
            `read_pct`   = :read_pct,
            `updated_at` = :updated_at
        SQL
        # rubocop:enable GitHub/InsertOnDuplicateKeyUpdate
        ActiveRecord::Base.connected_to(role: :writing) do
          ElastomerIndexMemo.connection.insert(query)
        end

        config
      end

      # Itereate over all the rows in the MySQL table and yield an IndexConfig
      # instance for each.
      #
      # Returns this MysqlStore instance.
      def each(&block)
        query = Arel.sql(<<-SQL, datacenter: datacenter)
          SELECT * FROM #{TABLE_NAME}
          WHERE datacenter = :datacenter
          ORDER BY `name` ASC
        SQL

        ElastomerIndexMemo.connection.select_all(query).each do |row|
          config = hydrate_config row
          yield config unless config.nil?
        end

        self
      end

      # Interanl: Given a database `row` from the "elastomer_index_memos" table,
      # create a new IndexConfig and return it. If the row is `nil` or empty,
      # then `nil` is returned.
      #
      # row - Database row as a Hash of column name => value
      #
      # Return a new IndexConfig instance.
      def hydrate_config(row)
        return if row.nil? || row.empty?

        read    = ActiveRecord::Type::Boolean.new.deserialize row["read"]
        write   = ActiveRecord::Type::Boolean.new.deserialize row["write"]
        primary = ActiveRecord::Type::Boolean.new.deserialize row["primary"]

        IndexConfig.new \
          name: row["name"],
          cluster: row["cluster"],
          version: row["version"],
          read: read,
          write: write,
          primary: primary,
          read_pct: row["read_pct"] || 0
      end

      private

      def datacenter
        GitHub.es_datacenter
      end
    end
  end
end
