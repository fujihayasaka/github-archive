# typed: true
# frozen_string_literal: true

class AddCliRemoteControlToCopilotConfigurations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :cli_remote_control, :integer, limit: 1, null: false, default: 0,
        comment: "Enable Copilot CLI remote control — allows CLI sessions to be monitored and steered from cloud-based clients (Organization or Business)"
    end
  end
end
