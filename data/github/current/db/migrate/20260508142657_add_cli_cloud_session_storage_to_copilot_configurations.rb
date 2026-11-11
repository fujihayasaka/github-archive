# typed: true
# frozen_string_literal: true

class AddCliCloudSessionStorageToCopilotConfigurations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :cli_cloud_session_storage, :integer, limit: 1, null: false, default: 0,
        comment: "Enable storing CLI and VSCode sessions in the cloud."
    end
  end
end
