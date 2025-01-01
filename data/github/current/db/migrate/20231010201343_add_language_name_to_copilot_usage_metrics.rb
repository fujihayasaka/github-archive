class AddLanguageNameToCopilotUsageMetrics < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_usage_metrics, bulk: true do |t|
      t.string :language, null: true, limit: 100, comment: "The language this usage metric is for (if no matching LanguageName)"
    end
  end
end
