# typed: true

class DropMobileDeviceTokens < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Notifications)

  def change
    drop_table :mobile_device_tokens
  end
end
