class AddGitHubEnterpriseFeatureGroupToCopilotPolicies < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :github_enterprise_feature_group, :integer, limit: 1, null: false, default: 0, comment: "Keep track if the group of enterprise features has been enabled"
    end
  end
end
