# typed: true
# frozen_string_literal: true

class AddSecurityComplianceFieldsToMarketplaceListing < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    change_table :marketplace_listings, bulk: true do |t|
      t.column :trader_self_certification, :integer
      t.column :trader_address, :string
      t.column :trader_id_type, :string
      t.column :trader_id, :string
      t.column :has_eu_compliance_attestation, :boolean, default: false, null: false
    end
  end
end
