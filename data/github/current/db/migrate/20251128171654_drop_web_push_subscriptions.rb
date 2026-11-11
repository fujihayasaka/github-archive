# typed: true

class DropWebPushSubscriptions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Ballast)

  def change
    drop_table :web_push_subscriptions, if_exists: true
  end
end
