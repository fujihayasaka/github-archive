class AddBetaFeaturesGitHubChatToCopilotConfigurations < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :beta_features_github_chat, :integer, limit: 1, null: false, default: 0, comment: "policy for beta features usage by Copilot in GitHub"
    end
  end
end
