# typed: true
# frozen_string_literal: true

class AddBillableCustomerToCopilotConfig < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :billable_customer_id, :bigint, unsigned: true, comment: "The customer that will be billed for this user"
    end
  end
end
