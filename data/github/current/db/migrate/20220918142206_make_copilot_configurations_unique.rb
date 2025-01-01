# typed: true

class MakeCopilotConfigurationsUnique < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.remove_index [:configurable_id, :configurable_type], name: "index_copilot_configurations_on_configurable"
      t.index        [:configurable_id, :configurable_type], name: "uniq_index_copilot_configurations_on_configurable", unique: true
    end
  end
end
