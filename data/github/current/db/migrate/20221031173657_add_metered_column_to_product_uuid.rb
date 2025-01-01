# typed: true
class AddMeteredColumnToProductUUID < ActiveRecord::Migration[7.1]
  def change
    add_column :product_uuids, :metered, :boolean, null: false, default: false
  end
end
