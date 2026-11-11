# typed: true
# frozen_string_literal: true

class AddSpacesToCopilotConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :spaces, :integer, limit: 1, null: false, default: 0, comment: "The policy for allowing Copilot Spaces for members of an organization"
    end
  end
end
