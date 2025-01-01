# typed: true
class ModifyRequiredWorkflowsColumns < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)
  def up
    change_table :required_workflows, bulk: true do |t|
      t.change :name, "varchar(1024)", null: false
      t.integer :state, limit: 1, null: false, default: 0
      t.remove :is_deleted
    end
  end

  def down
    change_table :required_workflows, bulk: true do |t|
      t.change :name, "varbinary(1024)", null: false
      t.remove :state
      t.integer :is_deleted, limit: 1, null: false, default: 0
    end
  end
end
