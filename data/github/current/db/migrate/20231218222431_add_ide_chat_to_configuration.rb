#typed: true
class AddIdeChatToConfiguration < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    add_column :copilot_configurations, :ide_chat, :tinyint, default: 2, null: false
  end
end
