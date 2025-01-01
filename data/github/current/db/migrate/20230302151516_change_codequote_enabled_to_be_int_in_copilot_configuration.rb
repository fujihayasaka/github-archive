# typed: true

class ChangeCodequoteEnabledToBeIntInCopilotConfiguration < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def up
    change_column :copilot_configurations, :codequote_enabled, :integer, default: 0, null: false
  end

  def down
    change_column :copilot_configurations, :codequote_enabled, :boolean, default: false, null: false
  end
end
