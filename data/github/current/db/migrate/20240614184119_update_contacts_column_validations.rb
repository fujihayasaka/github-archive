# typed: true
# frozen_string_literal: true

class UpdateContactsColumnValidations < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    change_table :contacts, bulk: true do |t|
      t.change :first_name, :string, limit: 64, null: true
      t.change :last_name, :string, limit: 64, null: true
      t.change :entity_name, :string, limit: 800, null: true
      t.change :address1, :string, limit: 128, null: true
      t.change :address2, :string, limit: 128, null: true
      t.change :city, :string, limit: 64, null: true
      t.change :region, :string, limit: 64, null: true
      t.change :postal_code, :string, limit: 32, null: true
      t.change :country_code, :string, limit: 3, null: true
    end
  end
end
