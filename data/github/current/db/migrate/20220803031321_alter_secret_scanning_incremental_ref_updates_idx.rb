# typed: true
class AlterSecretScanningIncrementalRefUpdatesIdx < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def up
    change_table :secret_scanning_incremental_scan_ref_updates, bulk: true do |t|
      t.change :before_commit, "varbinary(32)", null: false, default: "", comment: "sha1 or sha256 of the commit before the ref update; if len is 20, its sha1"
      t.remove_index [:scan_id], name: "idx_incremental_scan_ref_updates_scan_id"
      t.index [:scan_id, :ref_xxhash, :before_commit, :after_commit,], unique: true, name: "unique_idx_incremental_scan_ref_updates", comment: "natural key for this table is scan, ref (hash) before and after commits"
    end
  end

  def down
    change_table :secret_scanning_incremental_scan_ref_updates, bulk: true do |t|
      t.change :before_commit, "varbinary(32)", null: true, comment: "sha1 or sha256 of the commit before the ref update; if len is 20, its sha1"
      t.remove_index name: "unique_idx_incremental_scan_ref_updates"
      t.index [:scan_id], name: "idx_incremental_scan_ref_updates_scan_id"
    end
  end
end
