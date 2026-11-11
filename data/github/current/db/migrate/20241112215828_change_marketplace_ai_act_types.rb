# typed: true
# frozen_string_literal: true

class ChangeMarketplaceAiActTypes < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def up
    change_table :marketplace_listings, bulk: true do |t|
      t.remove :is_high_risk_ai
      t.column :ai_risk_level, :integer, default: 0, null: false

      t.change :repository_visibility, :integer, default: 0, null: false
    end
  end

  def down
    change_table :marketplace_listings, bulk: true do |t|
      t.column :is_high_risk_ai, :boolean, default: false, null: false
      t.remove :ai_risk_level

      t.change :repository_visibility, :boolean, default: false, null: false
    end
  end
end
