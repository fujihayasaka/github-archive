# typed: true
# frozen_string_literal: true

class CopilotUsageDropUnusedIndicies < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_usage_metrics, bulk: true do |t|
      t.remove_index name: :index_copilot_usage_metrics_on_language_name_id, column: :language_name_id
      t.remove_index name: :index_copilot_usage_metrics_on_editor, column: :editor
      t.remove_index name: :schema_version, column: :schema_version
    end
  end
end
