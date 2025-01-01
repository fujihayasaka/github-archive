# typed: true
# frozen_string_literal: true

class ChangeCouponRedemptionsBooleansToSigned < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Mysql1)

  def up
    change_table :coupon_redemptions, bulk: true do |t|
      t.change :id, "bigint(20) unsigned NOT NULL AUTO_INCREMENT"
      t.change :user_id, "bigint(20) unsigned DEFAULT NULL"
      t.change :coupon_id, "bigint(20) unsigned DEFAULT NULL"
      t.change :expired, "tinyint(1) DEFAULT '0'"
    end
  end

  def down
    change_table :coupon_redemptions, bulk: true do |t|
      t.change :id, "int(11) unsigned NOT NULL AUTO_INCREMENT"
      t.change :user_id, "int(11) unsigned DEFAULT NULL"
      t.change :coupon_id, "int(11) unsigned DEFAULT NULL"
      t.change :expired, "tinyint(1) unsigned DEFAULT '0'"
    end
  end
end
