# typed: true
# frozen_string_literal: true

class CreateCopilotMonitoredUsersTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :copilot_monitored_users, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :user, type: :bigint, unsigned: true, null: false, index: { unique: true }
      t.timestamps
    end
  end
end
