# typed: true

class AddScanJobGroupToCustomPatterns < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def change
    change_table :secret_scan_custom_patterns, bulk: true do |t|
      t.index :scan_id, comment: "supports reverse lookups by scan_id via the scans table"
      t.index :job_group_id, comment: "supports reverse lookups by job_group_id via the job_groups table"
    end
  end
end
