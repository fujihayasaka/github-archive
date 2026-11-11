# typed: true

class CreateCopilotAgentSessions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    create_table :copilot_agent_sessions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :business_id, :bigint, unsigned: true, null: true
      t.column :organization_id, :bigint, unsigned: true, null: false
      t.column :repository_id, :bigint, unsigned: true, null: false
      t.column :user_id, :bigint, unsigned: true, null: false
      t.column :agent_id, :bigint, unsigned: true, null: false

      # polymorphic association which only supports pull_request today
      t.column :resource_id, :bigint, unsigned: true, null: false
      t.column :resource_type, "enum('PullRequest')", null: false

      t.string :copilot_session_id, null: false
      t.string :name, limit: 100, null: false
      t.string :state, limit: 20, null: false
      t.string :task_description, limit: 50

      t.timestamps

      t.index [:business_id, :organization_id]
      t.index [:business_id, :agent_id]
      t.index [:business_id, :task_description]
      t.index [:resource_id, :resource_type]
    end
  end
end
