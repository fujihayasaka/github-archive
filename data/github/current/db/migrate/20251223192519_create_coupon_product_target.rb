# typed: strict
# frozen_string_literal: true

class CreateCouponProductTarget < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Billing)

  sig { void }
  def change
    create_table :coupon_product_targets, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :coupon_id, unsigned: true, null: false
      t.string :product_type, null: false, limit: 32
      t.string :product_key, null: false, limit: 64

      t.index [:product_type, :product_key]
      t.index [:coupon_id, :product_type, :product_key], unique: true

      t.timestamps
    end
  end
end
