# typed: true

class AddRemovalDateToMarketplaceListings < ActiveRecord::Migration[7.1]
  def change
    change_table :marketplace_listings, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :primary_category_id, :bigint, unsigned: true
      t.change :secondary_category_id, :bigint, unsigned: true
      t.change :hero_card_background_image_id, :bigint, unsigned: true
      t.change :listable_id, :bigint, unsigned: true
      t.column :removal_date, :datetime, precision: 6
    end
  end
end
