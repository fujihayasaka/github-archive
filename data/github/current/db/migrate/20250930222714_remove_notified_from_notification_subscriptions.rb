# typed: true

class RemoveNotifiedFromNotificationSubscriptions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Notifications)

  def up
    change_table :notification_subscriptions, bulk: true do |t|
      t.remove_index name: "index_notification_subscriptions_on_notified_list_type_and_user"
      t.remove_index name: "index_notification_subscriptions_on_notified_and_user_id"

      t.remove :notified
    end
  end

  def down
    change_table :notification_subscriptions, bulk: true do |t|
      t.column :notified, :boolean, default: true, null: true

      t.index [:notified, :list_type, :user_id], name: "index_notification_subscriptions_on_notified_list_type_and_user"
      t.index  [:notified, :user_id], name: "index_notification_subscriptions_on_notified_and_user_id"
    end
  end
end
