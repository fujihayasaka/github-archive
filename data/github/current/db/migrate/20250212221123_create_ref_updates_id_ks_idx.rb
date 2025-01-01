# typed: true

class CreateRefUpdatesIdKsIdx < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def change
    create_table :ref_updates_id_ks_idx, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    # Primary vindex for keyspace table.
    add_vindex :ref_updates_id_ks_idx, :hash, :id

    # Lookup vindex for keyspace table. The "owner" table needs to exist before this migration is run.
    create_vindex :ref_updates_id_ks_idx, :lookup_unique, owner: "ref_updates", from: "id", table: "ref_updates_id_ks_idx", to: "keyspace_id", autocommit: true, read_lock: "none"

    # Column vindex for "owner" table. This table needs to exist before this migration is run.
    add_vindex :ref_updates, :ref_updates_id_ks_idx, :id
  end
end
