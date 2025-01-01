# typed: true
class SecretScanCustomPatternsPrecompiledDb < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::TokenScanningService)

  def up
    change_table(:secret_scan_custom_patterns, bulk: true) do |t|
      t.column :block_database, "mediumblob", null: true,  comment: "the marshaled and gzip'd hyperscan BlockDatabase"
    end
  end

  def down
    change_table(:secret_scan_custom_patterns, bulk: true) do |t|
      t.remove :block_database
    end
  end
end
