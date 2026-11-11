class AddCopilotPlanToCopilotBusinessTrials < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_business_trials, bulk: true do |t|
      t.column :copilot_plan, :tinyint, default: 0, null: false, after: :id, comment: "the GitHub Copilot plan the trial is for, e.g. Copilot Enterprise or Copilot Business"
    end
  end
end
