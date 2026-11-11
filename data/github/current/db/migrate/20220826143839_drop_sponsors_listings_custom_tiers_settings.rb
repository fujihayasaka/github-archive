# typed: true
# frozen_string_literal: true

class DropSponsorsListingsCustomTiersSettings < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def up
    change_table(:sponsors_listings, bulk: true) do |t|
      t.remove :custom_tiers_allowed
      t.remove :custom_tiers_frequency
    end
  end

  def down
    change_table(:sponsors_listings, bulk: true) do |t|
      t.column :custom_tiers_allowed, :boolean, null: false, default: false, after: :country_of_residence
      t.column :custom_tiers_frequency, :tinyint, null: false, default: 0, after: :custom_tiers_allowed
    end
  end
end
