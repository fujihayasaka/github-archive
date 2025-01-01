# typed: true
# frozen_string_literal: true

class AddLockedToRequiredWorkflows < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    add_column :required_workflows, :locked, "tinyint(1)", null: false, default: 0
  end
end
