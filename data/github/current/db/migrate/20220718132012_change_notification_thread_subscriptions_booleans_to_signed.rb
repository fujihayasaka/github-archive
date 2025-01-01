# typed: true
# frozen_string_literal: true

class ChangeNotificationThreadSubscriptionsBooleansToSigned < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Mysql2)

  def up
    change_table :notification_thread_subscriptions, bulk: true do |t|
      t.change :user_id, "bigint(20) unsigned NOT NULL"
      t.change :list_id, "bigint(20) unsigned NOT NULL"
      t.change :ignored, "tinyint(1) NOT NULL"
    end
  end

  def down
    change_table :notification_thread_subscriptions, bulk: true do |t|
      t.change :user_id, "int(11) unsigned NOT NULL"
      t.change :list_id, "int(11) unsigned NOT NULL"
      t.change :ignored, "tinyint(1) unsigned NOT NULL"
    end
  end
end
