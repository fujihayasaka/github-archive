# typed: true
# frozen_string_literal: true

class AddCcrDirectOrgBillingToCopilotConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :ccr_direct_org_billing, :integer, limit: 1, null: false, default: 0, comment: "Enable Copilot code review for all members of this organization, including those without a Copilot license (Organization or Business)"
    end
  end
end
