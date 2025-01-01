# typed: true
# frozen_string_literal: true

class CopilotUsageAddIndexOnSchemaVersionDate < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    add_index :copilot_usage_metrics, [:schema_version, :date], name: "index_schema_version_date" # rubocop:disable GitHub/AvoidRedundantIndex
  end
end
