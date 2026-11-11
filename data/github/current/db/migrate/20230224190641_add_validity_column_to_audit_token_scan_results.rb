# typed: true

class AddValidityColumnToAuditTokenScanResults < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::TokenScanningService)
  def up
    change_table(:audit_token_scan_results, bulk: true) do |t|
      t.column :validity, "tinyint(3)", null: true, comment: "internal enum/iota within the token-scanning-service representing validity"
    end
  end

  def down
    change_table(:audit_token_scan_results, bulk: true) do |t|
      t.remove :validity
    end
  end
end
