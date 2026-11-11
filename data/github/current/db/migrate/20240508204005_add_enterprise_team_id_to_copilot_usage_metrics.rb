class AddEnterpriseTeamIdToCopilotUsageMetrics < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_usage_metrics, bulk: true do |t|
      t.references :enterprise_team, index: { unique: false }, null: true, after: :team_id, comment: "The enterprise team that this usage metric is under"
    end
  end
end
