# typed: true
class AddCodequoteEnabledToCopilotConfiguration < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    add_column :copilot_configurations, :codequote_enabled, :boolean, null: false, default: false
  end
end
