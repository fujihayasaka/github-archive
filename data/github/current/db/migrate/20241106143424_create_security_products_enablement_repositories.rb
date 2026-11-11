# typed: true

class CreateSecurityProductsEnablementRepositories < ActiveRecord::Migration[8.0]
  use_connection_class ApplicationRecord::Domain::SecurityProductsEnablement

  def change
    create_table :security_products_enablement_repositories, primary_key: [:repository_id], charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.bigint :owner_id, unsigned: true, null: false
      t.bigint :business_id, unsigned: true, null: true
      t.bigint :security_configuration_id, unsigned: true, null: true
      t.integer :security_configuration_state, limit: 1, null: true
      t.timestamps

      t.index [:owner_id, :security_configuration_id, :security_configuration_state], name: "index_on_owner_and_config"
      t.index [:business_id, :security_configuration_id, :security_configuration_state], name: "index_on_business_and_config"
    end
  end
end
