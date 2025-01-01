# typed: true

# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
class CreateRepositorySecuritySettings < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::SecurityProductsEnablement

  def change
    create_table :repository_security_settings, primary_key: [:repository_id, :feature], charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.integer :feature, limit: 1, unsigned: true, null: false
      t.integer :state, limit: 1, unsigned: false, null: false
      t.integer :blocker, limit: 1, unsigned: false, null: true
      t.integer :failure, limit: 1, unsigned: false, null: true
    end
  end
end
