# typed: true
# frozen_string_literal: true

class AddExperimentalAutoModelsToCopilotConfigurations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :experimental_auto_models, :integer, limit: 1, null: false, default: 0,
        comment: "Policy setting for access to experimental auto models in Copilot."
    end
  end
end
