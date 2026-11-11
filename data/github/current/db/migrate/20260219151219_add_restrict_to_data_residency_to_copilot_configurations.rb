# typed: true
# frozen_string_literal: true

class AddRestrictToDataResidencyToCopilotConfigurations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :restrict_to_data_residency, :integer, limit: 1, null: false, default: 0, comment: "Whether to restrict this configurable to data residency compliant models only"
    end
  end
end
