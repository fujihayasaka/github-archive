# typed: true
# frozen_string_literal: true

class AddModelNativeSearchToCopilotConfigurations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :model_native_search, :integer, limit: 1, null: false, default: 0, comment: "policy for model native search usage by Copilot"
    end
  end
end
