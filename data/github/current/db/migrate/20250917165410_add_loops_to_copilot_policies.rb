# typed: true

class AddLoopsToCopilotPolicies < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :loops, :integer, limit: 1, null: false, default: 0, comment: "The policy for enabling or disabling Loops for members of an organization"
    end
  end
end
