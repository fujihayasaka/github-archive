# typed: true

class DropNotificationDeliveries < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::NotificationsDeliveries)

  def change
    drop_table :notification_deliveries
  end
end
