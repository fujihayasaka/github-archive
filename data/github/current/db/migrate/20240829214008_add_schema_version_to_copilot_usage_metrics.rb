# typed: true
# frozen_string_literal: true

class AddSchemaVersionToCopilotUsageMetrics < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_usage_metrics, bulk: true do |t|
      t.column :schema_version, :integer, null: true, comment: "Version of the schema present in the metadata column"
    end
  end
end
