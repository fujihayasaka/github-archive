# typed: true

class AddIndexToSecretScanningScans < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table :secret_scanning_scans, bulk: true do |t|
      t.index [:aqueduct_job_id], unique: false, name: "idx_scans_aqueduct_job_id", comment: "support aqueduct job id lookups"
      t.index [:created_at, :scan_status, :scan_type, :repository_id], unique: false, name: "idx_scans_created_status_type_repo"
    end
  end

  def down
    change_table :secret_scanning_scans, bulk: true do |t|
      t.remove_index name: "idx_scans_aqueduct_job_id"
      t.remove_index name: "idx_scans_created_status_type_repo"
    end
  end
end
