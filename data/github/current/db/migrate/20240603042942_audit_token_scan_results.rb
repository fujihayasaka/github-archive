class AuditTokenScanResults < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def up
    change_table(:audit_token_scan_results, bulk: true) do |t|
      t.column :publicly_leaked, "tinyint(1)", null: false, default: 0, unsigned: true, comment: "whether this token has been leaked in a public repository"
      t.column :internally_leaked, "tinyint(1)", null: false, default: 0, unsigned: true, comment: "whether this token has been leaked in another repository within the same owner or enterprise"
    end
  end

  def down
    change_table(:audit_token_scan_results, bulk: true) do |t|
      t.remove :publicly_leaked
      t.remove :internally_leaked
    end
  end
end
