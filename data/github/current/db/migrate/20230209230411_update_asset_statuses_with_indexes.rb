# typed: true
# frozen_string_literal: true

class UpdateAssetStatusesWithIndexes < ActiveRecord::Migration[7.1]
  def up
    change_table :asset_statuses, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :owner_id, :bigint, unsigned: true, null: true

      t.index [:asset_type, :bandwidth_down],
        name: "index_asset_statuses_on_type_and_bandwidth_down"
      t.index [:asset_type, :bandwidth_up],
        name: "index_asset_statuses_on_type_and_bandwidth_up"
      t.index [:asset_type, :storage],
        name: "index_asset_statuses_on_type_and_storage"
    end
  end

  def down
    change_table :asset_statuses, bulk: true do |t|
      t.remove_index [:asset_type, :bandwidth_down],
        name: "index_asset_statuses_on_type_and_bandwidth_down"
      t.remove_index [:asset_type, :bandwidth_up],
        name: "index_asset_statuses_on_type_and_bandwidth_up"
      t.remove_index [:asset_type, :storage],
        name: "index_asset_statuses_on_type_and_storage"

      t.change :id, :integer, null: false, auto_increment: true
      t.change :owner_id, :integer, null: true
    end
  end
end
