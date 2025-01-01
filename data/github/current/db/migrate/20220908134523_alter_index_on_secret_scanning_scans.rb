# typed: true
class AlterIndexOnSecretScanningScans < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table :secret_scanning_scans, bulk: true do |t|
      t.remove_index name: "idx_scans_repo_status_type"
      t.index [:repository_id, :scan_status, :scan_type, :hcs_changelog_version], name: "idx_scans_repo_type_status_hcs_version"
    end
  end

  def down
    change_table :secret_scanning_scans, bulk: true do |t|
      t.remove_index name: "idx_scans_repo_type_status_hcs_version"
      t.index [:repository_id, :scan_status, :scan_type], name: "idx_scans_repo_status_type"
    end
  end
end
