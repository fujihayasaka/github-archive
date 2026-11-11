# typed: strict
# frozen_string_literal: true

class AddCouponableToProductUUID < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  sig { void }
  def change
    change_table :product_uuids, bulk: true do |t|
      t.boolean :couponable, default: false, null: false

      t.index :couponable
    end
  end
end
