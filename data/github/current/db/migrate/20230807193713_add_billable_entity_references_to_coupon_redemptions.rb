# typed: true

class AddBillableEntityReferencesToCouponRedemptions < ActiveRecord::Migration[7.1]
  def change
    change_table :coupon_redemptions, bulk: true do |t|
      t.belongs_to :billable_entity, polymorphic: true, unsigned: true, index: false
    end

    add_index :coupon_redemptions, [:billable_entity_id, :billable_entity_type, :coupon_id], name: :index_coupon_redemptions_on_billable_entity_and_coupon_id
  end
end
