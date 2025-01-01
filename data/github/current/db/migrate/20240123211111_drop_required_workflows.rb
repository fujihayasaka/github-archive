class DropRequiredWorkflows < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    drop_table :required_workflows, if_exists: true
  end
end
