# typed: true

class AddSparkForceOrgSettingToCopilotPolicy < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :spark_force_org, :integer, limit: 1, null: false, default: 0, comment: "Policy for forcing Spark repo creation to the copilot providing organization instead of the user"
    end
  end
end
