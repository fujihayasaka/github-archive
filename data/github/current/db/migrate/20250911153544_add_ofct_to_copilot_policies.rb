# typed: true
# frozen_string_literal: true

class AddOfctToCopilotPolicies < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :ofct, :integer, limit: 1, null: false, default: 0
    end
  end
end
