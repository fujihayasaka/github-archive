# typed: true
class CreateRequiredWorkflows < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)
  def up
    create_table :required_workflows, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.unsigned_bigint :owner_id, null: false
      t.column :name, "varbinary(1024)", null: false
      t.column :path, "varbinary(1024)", null: false
      t.unsigned_bigint :repository_id, null: false
      t.integer :scope, limit: 1, null: false, default: 0, comment: "Can be 0 or 1. 0 indicates all repositories and 1 indicates selected repositories"
      t.column :ref, "varbinary(1024)", null: false, comment: "Ref at which the required workflow was selected"
      t.column :is_deleted, :boolean, default: false, null: false
      t.timestamps

      t.index [:owner_id, :repository_id], name: "index_on_owner_id_and_repository_id"
    end
  end

  def down
    drop_table :required_workflows
  end
end
