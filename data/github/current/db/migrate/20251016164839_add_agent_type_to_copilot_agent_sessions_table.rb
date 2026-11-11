# typed: true

class AddAgentTypeToCopilotAgentSessionsTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def up
    change_table :copilot_agent_sessions, bulk: true do |t|
      t.column :agent_type, "enum('Integration','OauthApplication')", null: false, default: "Integration", after: :agent_id
      t.column :event_type, "varbinary(128)", null: true

      t.change :resource_id, :bigint, unsigned: true, null: true
      t.change :resource_type, "enum('PullRequest')", null: true
    end
  end

  def down
    change_table :copilot_agent_sessions, bulk: true do |t|
      t.remove :agent_type
      t.remove :event_type

      t.change :resource_id, :bigint, unsigned: true, null: false
      t.change :resource_type, "enum('PullRequest')", null: false
    end
  end
end
