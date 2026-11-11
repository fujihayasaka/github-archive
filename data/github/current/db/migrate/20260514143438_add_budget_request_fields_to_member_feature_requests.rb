# typed: true
# frozen_string_literal: true

class AddBudgetRequestFieldsToMemberFeatureRequests < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :member_feature_requests, bulk: true do |t|
      t.column :request_type, :integer, limit: 1, unsigned: true, null: false, default: 0,
        comment: "enum: 0=feature_unlock, 1=additional_budget"
      t.column :requested_amount_cents, :integer, unsigned: true, null: true,
        comment: "requested budget amount in cents, required for additional_budget request_type"
    end
  end
end
