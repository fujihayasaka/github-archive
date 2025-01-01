# typed: true
# frozen_string_literal: true

class AddOrgColumnToExemptionRequests < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :exemption_requests, bulk: true do |t|
      t.bigint :business_id, unsigned: true, null: true, default: nil
      t.bigint :owner_id, unsigned: true, null: false, default: 0

      t.index [:business_id, :owner_id, :repository_id], name: "index_exemption_requests_business_owner_repository"
    end
  end
end
