# typed: true
# frozen_string_literal: true

class CreateContacts < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    create_table :contacts, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :customer_id, unsigned: true, null: false
      t.column :address_type, :tinyint, null: false
      t.column :first_name, :string, limit: 64, null: false
      t.column :last_name, :string, limit: 64, null: false
      t.column :entity_name, :string, limit: 800, null: false
      t.column :address1, :string, limit: 128, null: false
      t.column :address2, :string, limit: 128, null: false
      t.column :city, :string, limit: 64, null: false
      t.column :region, :string, limit: 64, null: false
      t.column :postal_code, :string, limit: 32, null: false
      t.column :country_code, :string, limit: 3, null: false
      t.column :trade_screening_status, :tinyint, null: false, default: 0
      t.column :address_validated_at, :datetime, precision: 6, default: nil

      t.index [:customer_id, :address_type], unique: true

      t.timestamps
    end
  end
end
