# typed: true
# frozen_string_literal: true

class UpdateMultiTenantProvisioningRequests < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table :multi_tenant_provisioning_requests, bulk: true do |t|
      t.change :subdomain, :string, null: false, limit: 60
      t.column :other_industry, :string, null: true, limit: 255, after: :industry
      t.column :staff_owned, :boolean, null: false, default: false
    end
  end

  def down
    change_table :multi_tenant_provisioning_requests, bulk: true do |t|
      t.change :subdomain, :string, null: false, limit: 32
      t.remove :other_industry
      t.remove :staff_owned
    end
  end
end
