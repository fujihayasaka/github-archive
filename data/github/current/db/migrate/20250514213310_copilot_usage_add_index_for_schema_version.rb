# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/AvoidRedundantIndex
# will remove in https://github.com/github/github/pull/378354

class CopilotUsageAddIndexForSchemaVersion < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_usage_metrics, bulk: true do |t|
      t.index :schema_version, name: "schema_version"
    end
  end
end
