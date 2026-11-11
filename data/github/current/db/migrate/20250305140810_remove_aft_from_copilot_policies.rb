# typed: true

class RemoveAftFromCopilotPolicies < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def up
    remove_column :copilot_configurations, :a_ft, :integer
  end

  def down
    add_column :copilot_configurations, :a_ft, :integer
  end
end
