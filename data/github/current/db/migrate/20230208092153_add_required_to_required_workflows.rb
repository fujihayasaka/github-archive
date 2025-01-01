# typed: true
# frozen_string_literal: true

class AddRequiredToRequiredWorkflows < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    change_table :required_workflows, bulk: true do |t|
      t.column :required, "tinyint(1)", null: false, default: 1
    end
  end

  def down
    change_table :required_workflows, bulk: true do |t|
      t.remove_column :required
    end
  end
end
