class AddUserFeedbackOptInToCopilotConfigurations < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :user_feedback_opt_in, :integer, limit: 1, null: false, default: 1, comment: "policy for GitHub Copilot for user feedback opt in"
    end
  end
end
