class AddTeamIdAndChatToCopilotUsageMetrics < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_usage_metrics, bulk: true do |t|
      t.references :team, index: { unique: false }, null: true, after: :organization_id, comment: "The team that this usage metric is under"
      t.integer    :chat_messages, null: false, default: 0, after: :active_users, comment: "The number of chat messages sent"
      t.integer    :chat_active_users, null: false, default: 0, after: :chat_messages, comment: "The number of active chat users"
    end
  end
end
