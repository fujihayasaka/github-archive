# typed: true
# frozen_string_literal: true

class DropUserIdFromCouponRedemption < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :coupon_redemptions, bulk: true do |t|
      t.remove_index [:user_id, :coupon_id]
      t.remove :user_id, type: :bigint, unsigned: true
    end
  end
end
