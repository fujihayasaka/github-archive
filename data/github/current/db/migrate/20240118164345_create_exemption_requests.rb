# typed: true

class CreateExemptionRequests < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    create_table :exemption_requests, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :number, unsigned: true
      t.string :request_type, limit: 255, null: false
      t.bigint :repository_id, unsigned: true
      t.bigint :resource_owner_id, unsigned: true
      t.string :resource_owner_type, limit: 64
      t.bigint :requester_id, null: false, unsigned: true
      t.string :requester_comment, limit: 2048
      t.string :resource_identifier, limit: 255
      t.column :status, :tinyint, null: false, unsigned: true, default: 0
      t.column :expires_at, :datetime, precision: 6, null: true
      t.json :metadata
      t.timestamps

      t.index [:resource_owner_id, :resource_owner_type, :expires_at], name: "index_exemption_requests_resource_owner"
      t.index [:request_type, :resource_identifier, :expires_at], name: "index_exemption_requests_resource_identifier"
      t.index [:repository_id, :expires_at], name: "index_exemption_requests_repository"
      t.index [:repository_id, :number], name: "index_exemption_requests_repository_number"
    end
  end
end
