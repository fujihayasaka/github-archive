# typed: true

class AddIndexForRepositoryIdInRequiredWorkflowRepositories < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    change_table :required_workflow_repositories, bulk: true do |t|
      t.index [:owner_id, :imposee_repository_id], name: "index_on_owner_id_and_imposee_repository_id"
    end
  end

  def down
    change_table :required_workflow_repositories, bulk: true do |t|
      t.remove_index name: "index_on_owner_id_and_imposee_repository_id"
    end
  end
end
