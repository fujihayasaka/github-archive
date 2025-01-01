# typed: true
class AddStateToCopilotBusinessTrials < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_business_trials, bulk: true do |t|
      t.column :state, :integer, null: false,  default: 0
      t.index :state
    end
  end
end
