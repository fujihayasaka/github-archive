# typed: true
# frozen_string_literal: true

class UseBigintsForSponsorsListingFeaturedItems < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def up
    change_table :sponsors_listing_featured_items, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :sponsors_listing_id, :bigint, unsigned: true
      t.change :featureable_id, :bigint, unsigned: true
    end
  end

  def down
    change_table :sponsors_listing_featured_items, bulk: true do |t|
      t.change :id, :int
      t.change :sponsors_listing_id, :int
      t.change :featureable_id, :int
    end
  end
end
