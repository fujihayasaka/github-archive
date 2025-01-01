# typed: true
# frozen_string_literal: true

class AddAiComplianceToMarketplaceListings < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    change_table :marketplace_listings, bulk: true do |t|
      t.column :is_high_risk_ai, :boolean, default: false, null: false
      t.column :llms_in_use, :string
      t.column :is_eu_ai_act_compliant, :boolean, default: false, null: false
      t.column :third_party_services, :string
      t.column :repository_visibility, :boolean, default: false, null: false
      t.column :repository_url, :string
      t.column :transparency_disclosure, :blob
    end
  end
end
