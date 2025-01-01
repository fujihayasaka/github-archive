# typed: true

class AddGChatToCopilotPolicies < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :g_chat, :integer, limit: 1, null: false, default: 0
    end
  end
end
