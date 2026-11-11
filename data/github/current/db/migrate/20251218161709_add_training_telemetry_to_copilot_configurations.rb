# typed: true
# frozen_string_literal: true

class AddTrainingTelemetryToCopilotConfigurations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :training_telemetry, :integer, limit: 1, null: false, default: 0, comment: "Controls whether GitHub collects telemetry data for model training processes."
    end
  end
end
