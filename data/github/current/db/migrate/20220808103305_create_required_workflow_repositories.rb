# typed: true

class CreateRequiredWorkflowRepositories < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)
  def up
    create_table :required_workflow_repositories, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.unsigned_bigint :owner_id, null: false
      t.unsigned_bigint :repository_id, null: false
      t.unsigned_bigint :required_workflow_id, null: false
      t.timestamps

      t.index [:required_workflow_id, :repository_id], unique: true, name: "index_on_required_workflow_id_and_repository_id"
    end
  end

  def down
    drop_table :required_workflow_repositories
  end
end
