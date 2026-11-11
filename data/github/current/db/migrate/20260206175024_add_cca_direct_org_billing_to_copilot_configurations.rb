# typed: true
# frozen_string_literal: true

class AddCcaDirectOrgBillingToCopilotConfigurations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :cca_direct_org_billing, :integer, limit: 1, null: false, default: 0, comment: "Enable Copilot code agent for all members of this organization, including those without a Copilot license (Organization or Business)"
    end
  end
end
