# typed: true
# frozen_string_literal: true

class ChangeNotificationSubscriptionsBooleansToSigned < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Mysql2)

  def up
    change_table :notification_subscriptions, bulk: true do |t|
      t.change :user_id, "bigint(20) unsigned NOT NULL"
      t.change :list_id, "bigint(20) unsigned NOT NULL"
      t.change :ignored, "tinyint(1) NOT NULL"
      t.change :notified, "tinyint(1) DEFAULT '1'"
    end
  end

  def down
    change_table :notification_subscriptions, bulk: true do |t|
      t.change :user_id, "int(11) unsigned NOT NULL"
      t.change :list_id, "int(11) unsigned NOT NULL"
      t.change :ignored, "tinyint(1) unsigned NOT NULL"
      t.change :notified, "tinyint(1) unsigned DEFAULT '1'"
    end
  end
end
