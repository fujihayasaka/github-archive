class AddPrFeatureFieldsToCopilotPolicies < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :pr_summarizations, :integer, limit: 1, null: false, default: 0, comment: "policy for GitHub Copilot for Pull Request Summarizations"
      t.column :pr_diff_chats, :integer, limit: 1, null: false, default: 0, comment: "policy for GitHub Copilot for Pull Request Diff Chat"
    end
  end
end
