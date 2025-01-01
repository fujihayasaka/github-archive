# typed: true
class ModifyRequiredWorkflowRepositoriesColumns < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)
  def up
    change_table :required_workflow_repositories, bulk: true do |t|
      t.remove_index [:required_workflow_id, :repository_id], name: "index_on_required_workflow_id_and_repository_id"
      t.remove :repository_id

      t.unsigned_bigint :imposee_repository_id, null: false
      t.index [:required_workflow_id, :imposee_repository_id], unique: true, name: "index_on_required_workflow_id_and_imposee_repository_id"
    end
  end

  def down
    change_table :required_workflow_repositories, bulk: true do |t|
      t.unsigned_bigint :repository_id, null: false
      t.index [:required_workflow_id, :repository_id], unique: true, name: "index_on_required_workflow_id_and_repository_id"

      t.remove_index [:required_workflow_id, :imposee_repository_id], name: "index_on_required_workflow_id_and_imposee_repository_id"
      t.remove :imposee_repository_id
    end
  end
end
