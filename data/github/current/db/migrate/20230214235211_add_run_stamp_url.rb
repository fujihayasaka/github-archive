# typed: true
class AddRunStampUrl < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def change
    add_column :workflow_run_executions, :run_stamp_url, "VARBINARY(1024)", null: true
  end
end
