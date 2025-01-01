# typed: true

class SecretScanningScansJobGroupIdx < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table :secret_scanning_scans, bulk: true do |t|
      t.remove_index name: "idx_scans_job_group_id"
      t.remove_index name: "idx_scans_repo_type_status_hcs_version"
      t.remove_index name: "idx_scans_created_status_type_repo"
      # Add repo ID to the job group index to make queries looking at multiple job groups for a single repo faster
      t.index [:job_group_id, :scan_status, :repository_id], unique: false, name: "idx_scans_job_group_id_status_repo"
      # swap scan type and scan status in the index so higher volume types (incremental) are eliminated in an earlier leaf
      # when looking for low-volume types.
      # re-creating the same idx_scans_repo_type_status_hcs_version that was dropped above
      t.index [:repository_id, :scan_type, :scan_status, :hcs_changelog_version], unique: false, name: "idx_scans_repo_type_status_hcs_version"
    end
  end

  def down
    change_table :secret_scanning_scans, bulk: true do |t|
      t.index [:created_at, :scan_status, :scan_type, :repository_id], unique: false, name: "idx_scans_created_status_type_repo"
      t.index [:job_group_id, :scan_status], unique: false, name: "idx_scans_job_group_id", comment: "supports job group processing by status"
      t.index [:repository_id, :scan_status, :scan_type, :hcs_changelog_version], unique: false, name: "idx_scans_repo_type_status_hcs_version"

      t.remove_index name: "idx_scans_job_group_id_status_repo"
      t.remove_index name: "idx_scans_repo_type_status_hcs_version"

    end
  end
end
