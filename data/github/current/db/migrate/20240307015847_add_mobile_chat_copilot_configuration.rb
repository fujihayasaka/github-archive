# typed: true

class AddMobileChatCopilotConfiguration < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :mobile_chat, :integer, limit: 1, null: false, default: 0, comment: "The policy for Copilot in Mobile"
    end
  end
end
