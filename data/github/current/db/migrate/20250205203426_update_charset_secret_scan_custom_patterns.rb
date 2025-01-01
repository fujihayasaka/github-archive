# typed: true

class UpdateCharsetSecretScanCustomPatterns < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table(:secret_scan_custom_patterns, bulk: true) do |t|
      t.change :dry_run_repositories, "varchar(255)", charset: "ascii", collation: "ascii_general_ci"
      t.change :row_version, "char(27)", charset: "ascii", collation: "ascii_general_ci"

      connection.execute "ALTER TABLE `secret_scan_custom_patterns` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci;"
    end
  end

  def down

    connection.execute "ALTER TABLE `secret_scan_custom_patterns` CONVERT TO CHARACTER SET utf8mb3;"
  end
end
