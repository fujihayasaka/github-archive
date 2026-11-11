# typed: true
# frozen_string_literal: true

class AddSpacesIndividualPoliciesToCopilotConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :spaces_individual_access, :integer, limit: 1, null: false, default: 0, comment: "The policy for allowing organization members to create individually owned Copilot Spaces"
      t.column :spaces_individual_sharing, :integer, limit: 1, null: false, default: 0, comment: "The policy for individual sharing in Copilot Spaces for members of an organization"
    end
  end
end
