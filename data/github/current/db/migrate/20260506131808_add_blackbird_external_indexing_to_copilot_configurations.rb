# typed: true
# frozen_string_literal: true

class AddBlackbirdExternalIndexingToCopilotConfigurations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :blackbird_external_indexing, :integer, limit: 1, null: false, default: 0,
        comment: "Policy setting for Blackbird external indexing."
    end
  end
end
