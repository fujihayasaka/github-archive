# typed: true

class DropMobilePushNotificationDeliveries < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::NotificationsDeliveries)

  def change
    drop_table :mobile_push_notification_deliveries, if_exists: true
  end
end
