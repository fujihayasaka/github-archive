# typed: true

class CreateRefUpdates < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def change
    create_table :ref_updates, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :push_id, :bigint, unsigned: true, null: false
      t.column :repository_id, :bigint, unsigned: true, null: false
      t.column :before_oid, "binary(20)", null: false
      t.column :after_oid, "binary(20)", null: false
      t.column :ref, "varbinary(1024)", null: false
      t.column :ref_update_type, :tinyint, unsigned: true, null: false
      t.index [:repository_id, :after_oid], name: "index_ref_updates_on_repository_id_and_after_oid"
      t.index [:repository_id, :ref], name: "index_ref_updates_on_repository_id_and_ref"
      t.index [:repository_id, :ref_update_type], name: "index_ref_updates_on_repository_id_and_ref_update_type"
      t.index [:push_id], name: "index_ref_updates_on_push_id"
    end

    add_vindex :ref_updates, :hash, :repository_id
    add_auto_increment :ref_updates, :id, :ref_updates_id_seq
  end
end
