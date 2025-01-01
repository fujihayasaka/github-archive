# typed: true

class AddSeatManagementSettingToCopilotConfiguration < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    add_column :copilot_configurations, :seat_management, :integer, default: 0, null: false
  end
end
