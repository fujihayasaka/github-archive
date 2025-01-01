# typed: true
class AddBaseOidToMergeGroupEntries < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    change_table :merge_group_entries, bulk: true do |t|
      t.column :base_oid, "varchar(40)", after: :retries

      # update ID columns to unsigned bigint as requested by GitHub/ExistingIdColumnsMustBeBigint rubocop.
      t.change :id, :bigint, unsigned: true
      t.change :merge_queue_id, :bigint, unsigned: true
      t.change :merge_group_id, :bigint, unsigned: true
      t.change :merge_queue_entry_id, :bigint, unsigned: true
    end
  end
end
