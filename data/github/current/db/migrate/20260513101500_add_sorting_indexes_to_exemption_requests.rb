# typed: true

class AddSortingIndexesToExemptionRequests < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :exemption_requests, bulk: true do |t|
      t.index [:business_id, :updated_at], name: "index_exemption_requests_business_updated_at"
      t.index [:business_id, :created_at], name: "index_exemption_requests_business_created_at"
      t.index [:owner_id, :updated_at], name: "index_exemption_requests_owner_updated_at"
      t.index [:owner_id, :created_at], name: "index_exemption_requests_owner_created_at"
      t.index [:repository_id, :updated_at], name: "index_exemption_requests_repository_updated_at"
      t.index [:repository_id, :created_at], name: "index_exemption_requests_repository_created_at"
    end
  end
end
