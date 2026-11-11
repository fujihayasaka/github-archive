class AddIndexToDateInUsageMetrics < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_usage_metrics, bulk: true do |t|
      # need this for deleting metrics by date in the usage service
      t.index :date, name: "index_copilot_usage_metrics_on_date"
      # need this for filtering by editor
      t.index :editor, name: "index_copilot_usage_metrics_on_editor"
    end
  end
end
