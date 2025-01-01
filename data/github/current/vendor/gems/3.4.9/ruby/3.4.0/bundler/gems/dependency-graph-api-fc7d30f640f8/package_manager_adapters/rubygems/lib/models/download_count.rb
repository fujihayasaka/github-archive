module Models
  class DownloadCount < Base
    def self.index?
      !connection.index_exists?(:download_counts, :version_id)
    end
    def self.generate
      connection.execute <<-SQL
        CREATE MATERIALIZED VIEW IF NOT EXISTS download_counts AS SELECT
          SUM(count) AS count,
          version_id
        FROM
          gem_downloads
        GROUP BY version_id;
      SQL

      if index?
        connection.add_index(:download_counts, :version_id)
      end
    end
  end
end
