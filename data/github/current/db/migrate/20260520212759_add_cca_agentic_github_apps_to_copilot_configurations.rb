# typed: true
# frozen_string_literal: true

class AddCcaAgenticGitHubAppsToCopilotConfigurations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :cca_agentic_github_apps, :integer, limit: 1, null: false, default: 0,
        comment: "If enabled, enterprise admins can turn on agentic features provided by GitHub Apps"
    end
  end
end
