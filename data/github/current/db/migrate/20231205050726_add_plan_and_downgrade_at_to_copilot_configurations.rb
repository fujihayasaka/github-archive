class AddPlanAndDowngradeAtToCopilotConfigurations < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :copilot_plan, :tinyint, default: 0, null: false, comment: "the current GitHub Copilot plan, e.g. Copilot Enterprise or Copilot Business"
      t.column :pending_plan_downgrade_date, :date, null: true, default: nil
    end
  end
end
