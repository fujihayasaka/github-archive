# typed: true

class AddSparkToCopilotPolicies < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :spark, :integer, limit: 1, null: false, default: 0, comment: "The policy for enabling or disabling Spark for members of an organization"
    end
  end
end
