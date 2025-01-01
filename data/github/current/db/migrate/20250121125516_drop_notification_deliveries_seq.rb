# typed: true

class DropNotificationDeliveriesSeq < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::VT)

  def change
    drop_table :notification_deliveries_seq
  end
end
