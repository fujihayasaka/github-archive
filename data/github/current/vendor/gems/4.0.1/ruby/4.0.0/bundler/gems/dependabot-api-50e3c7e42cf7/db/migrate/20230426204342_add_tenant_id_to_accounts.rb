# frozen_string_literal: true

class AddTenantIdToAccounts < ActiveRecord::Migration[7.0]
  def change
    add_column :accounts, :tenant_id, :bigint
  end
end
