# typed: true
# frozen_string_literal: true

class CreateMultiTenantProvisioningRequests < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    create_table :multi_tenant_provisioning_requests, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :name, :string, null: false, limit: 240
      t.column :subdomain, :string, null: false, limit: 32
      t.column :industry, :string, null: false, limit: 64
      t.column :number_of_seats, :string, null: false, limit: 16
      t.column :country_code, :string, null: false, limit: 3
      t.column :data_hosting_region, :tinyint, unsigned: true, null: false
      t.column :provisioning_step, :tinyint, unsigned: true, null: false, default: 0
      t.column :admin_name, :string, null: false, limit: 255
      t.column :admin_work_email, :string, null: false, limit: 255
      t.column :created_by_id, :bigint, unsigned: true, null: false

      t.timestamps

      t.index :subdomain, unique: true, name: "index_multi_tenant_provisioning_requests_on_subdomain"
      t.index :data_hosting_region, name: "index_multi_tenant_provisioning_requests_on_data_hosting_region"
      t.index :provisioning_step, name: "index_multi_tenant_provisioning_requests_on_provisioning_step"
    end
  end
end
