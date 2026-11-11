# typed: true
# frozen_string_literal: true

class CreateAgentSessionFinishedNotifications < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :agent_session_finished_notifications, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, null: false, unsigned: true
      t.bigint :repository_id, null: false, unsigned: true
      t.bigint :agent_id, null: false, unsigned: true  # AgenticApp integration ID
      t.bigint :pull_request_id, null: true, unsigned: true
      t.string :session_id, limit: 55, null: false
      t.string :task_id, limit: 55, null: false
      t.string :session_state, limit: 20, null: false
      t.timestamps

      t.index :session_id, unique: true
      t.index [:user_id, :created_at]
    end
  end
end
