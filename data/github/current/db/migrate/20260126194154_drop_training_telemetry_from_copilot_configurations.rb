# typed: true
# frozen_string_literal: true

class DropTrainingTelemetryFromCopilotConfigurations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)
  def up
    remove_column :copilot_configurations, :training_telemetry, :integer
  end

  def down
    add_column :copilot_configurations, :training_telemetry, :integer, limit: 1, null: false, default: 0, comment: "Controls whether GitHub collects telemetry data for model training processes."
  end
end
