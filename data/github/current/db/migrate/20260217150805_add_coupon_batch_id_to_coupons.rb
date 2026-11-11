# typed: strict
# frozen_string_literal: true

class AddCouponBatchIdToCoupons < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  sig { void }
  def up
    change_table :coupons, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.bigint :coupon_batch_id, unsigned: true, null: true
      t.index :coupon_batch_id
    end
  end

  sig { void }
  def down
    change_table :coupons, bulk: true do |t|
      t.remove_index :coupon_batch_id
      t.remove :coupon_batch_id
      t.change :id, :integer, unsigned: true, null: false, auto_increment: true
    end
  end
end
