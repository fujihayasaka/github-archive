# typed: true

class CreateSeatEmissions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    create_table :seat_emissions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string     :unique_id, limit: 36, null: false, comment: "UUID - The unique ID of the seat emission"
      t.references :business, null: false, index: false, comment: "The enterprise that this seat emission is for"
      t.column     :product_sku, "enum('ghec.seats')", null: false, index: true, comment: "The product SKU for the seat emission"
      t.integer    :seat_count, null: false, default: 0, comment: "The actual number of seats billed today"
      t.decimal    :quantity, precision: 22, scale: 9, null: false, comment: "The seat_count/days-in-billing-cycle"
      t.datetime   :usage_at, precision: 6, null: false, comment: "The datetime that the seat emission is for"

      t.timestamps

      t.index :unique_id, unique: true, name: "index_seat_emissions_on_unique_id"
      t.index [:business_id, :product_sku, :usage_at], unique: true, name: "index_seat_emissions_on_business_product_sku_usage_at"
    end
  end
end
