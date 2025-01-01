class DropMobilePushNotificationDeliveriesSeq < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::VT)

  def change
    drop_table :mobile_push_notification_deliveries_seq
  end
end
