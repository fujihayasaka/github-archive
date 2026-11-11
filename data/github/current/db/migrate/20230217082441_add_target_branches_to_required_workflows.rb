# typed: true

class AddTargetBranchesToRequiredWorkflows < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    add_column :required_workflows, :target_branches, "varbinary(1024)", null: false, default: ""
  end

  def down
    remove_column :required_workflows, :target_branches
  end
end
