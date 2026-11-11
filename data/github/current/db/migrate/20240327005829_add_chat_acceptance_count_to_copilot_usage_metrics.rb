class AddChatAcceptanceCountToCopilotUsageMetrics < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_usage_metrics, bulk: true do |t|
      t.integer    :chat_acceptances, null: false, default: 0, after: :chat_active_users, comment: "The number of chat messages sent"
    end
  end
end
