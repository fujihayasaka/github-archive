# typed: strict
# frozen_string_literal: true

class CreateCouponBatches < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Billing)

  sig { void }
  def change
    create_table :coupon_batches, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :prefix, limit: 64
      t.integer :quantity, null: false, unsigned: true
      t.text :generation_params, null: false
      t.string :tracking_issue, limit: 512
      t.bigint :actor_id, null: false, unsigned: true
      t.integer :status, null: false, unsigned: true, default: 0
      t.string :status_message, limit: 1024

      t.timestamps
    end
  end
end
