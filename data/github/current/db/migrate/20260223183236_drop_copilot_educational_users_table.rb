# typed: true
# frozen_string_literal: true

class DropCopilotEducationalUsersTable < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    drop_table :copilot_educational_users, if_exists: true
  end
end
