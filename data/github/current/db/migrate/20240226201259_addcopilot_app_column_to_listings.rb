class AddcopilotAppColumnToListings < ActiveRecord::Migration[7.2]
  def change
    add_column :marketplace_listings, :copilot_app, :boolean, null: false, default: false
  end
end
