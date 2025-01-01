# typed: true
class CreateVirtualNetworks < ActiveRecord::Migration[7.1]
  def change
    # String lengths are based on https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules
    create_table :virtual_networks, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :business_id, null: false, unsigned: true
      # example: /subscriptions/d656837c-c26c-48fd-8e7f-072b0e232614/resourceGroups/TestResourceGroup/providers/Microsoft.Network/virtualNetworks/TestVNet9default
      #          |-------------- 67 -----------------------------------------------|---- max 80 ---- |--------- 45 ------------------------------| -- max 80 ----|
      #  In theory, the max length is:  67 + 80 + 45 + 80 = 272
      t.string :subnet_id, null: false, limit: 300 # to be safe
      t.string :subnet_name, null: false, limit: 80
      # example: d656837c-c26c-48fd-8e7f-072b0e232614
      t.string :subscription_id, null: false, limit: 36
      t.string :subscription_name, null: false, limit: 80
      t.string :virtual_network_name, null: false, limit: 80
      t.column :organization_visibility, "enum('all', 'selected')", null: true
      t.timestamps
    end

    add_index :virtual_networks, [:business_id, :subnet_id], unique: true
  end
end
