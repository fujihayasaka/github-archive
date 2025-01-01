# typed: true

class CreateChangeStacks < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Ballast)

  def change
    create_table :change_stacks, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.bigint :user_id, unsigned: true, null: false
      t.column :uuid, "char(36)", null: false

      t.column :head_ref, "varbinary(1024)", null: false
      t.column :head_oid, "char(40)", null: false
      t.column :base_ref, "varbinary(1024)", null: false
      t.column :base_oid, "char(40)", null: false

      t.string :title

      t.timestamps null: false
    end
  end
end
