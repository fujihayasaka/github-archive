# typed: true
# frozen_string_literal: true

class AddOrgAndBizIdsToCopilotPremiumRequestsTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_premium_interactions, bulk: true do |t|
      unless column_exists?(:copilot_premium_interactions, :organization_id)
        t.bigint :organization_id, unsigned: true, null: true, comment: "ID of the Organization, used for usage reports"
      end
      t.bigint :business_id, unsigned: true, null: true, comment: "ID of the Business, used for usage reports"
    end
  end
end
