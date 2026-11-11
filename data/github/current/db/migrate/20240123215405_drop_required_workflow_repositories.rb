class DropRequiredWorkflowRepositories < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    drop_table :required_workflow_repositories, if_exists: true
  end
end
