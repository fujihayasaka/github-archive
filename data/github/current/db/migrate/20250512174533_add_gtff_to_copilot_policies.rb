# typed: true
# frozen_string_literal: true

class AddGtffToCopilotPolicies < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :gtff, :integer, limit: 1, null: false, default: 0, comment: "Policy for Gemini 2.5 Flash in Copilot"
    end
  end
end
