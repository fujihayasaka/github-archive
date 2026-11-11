class CreateBillingPlatformEnabledProducts < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    create_table :billing_platform_enabled_products, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.boolean :actions, null: true, default: nil
      t.boolean :git_lfs, null: true, default: nil
      t.boolean :copilot, null: true, default: nil
      t.boolean :packages, null: true, default: nil
      t.boolean :codespaces, null: true, default: nil
      t.boolean :ghec, null: true, default: nil
      t.boolean :ghas, null: true, default: nil
      t.boolean :shared_storage, null: true, default: nil
      t.bigint :customer_id, unsigned: true, index: { unique: true }, null: false
      t.timestamps
    end

    add_index :billing_platform_enabled_products, [:customer_id, :actions], name: "index_customer_id_actions", unique: true
    add_index :billing_platform_enabled_products, [:customer_id, :git_lfs], name: "index_customer_id_git_lfs", unique: true
    add_index :billing_platform_enabled_products, [:customer_id, :copilot], name: "index_customer_id_copilot", unique: true
    add_index :billing_platform_enabled_products, [:customer_id, :packages], name: "index_customer_id_packages", unique: true
    add_index :billing_platform_enabled_products, [:customer_id, :codespaces], name: "index_customer_id_codespaces", unique: true
    add_index :billing_platform_enabled_products, [:customer_id, :ghec], name: "index_customer_id_ghec", unique: true
    add_index :billing_platform_enabled_products, [:customer_id, :ghas], name: "index_customer_id_ghas", unique: true
    add_index :billing_platform_enabled_products, [:customer_id, :shared_storage], name: "index_customer_id_shared_storage", unique: true
  end
end
