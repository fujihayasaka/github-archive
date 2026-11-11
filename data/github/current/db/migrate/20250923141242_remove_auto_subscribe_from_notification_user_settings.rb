# typed: true

class RemoveAutoSubscribeFromNotificationUserSettings < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Notifications)

  def up
    change_table :notification_user_settings, bulk: true do |t|
      t.remove :auto_subscribe
      t.remove :auto_subscribe_teams
    end
  end

  def down
    change_table :notification_user_settings, bulk: true do |t|
      t.column :auto_subscribe, :boolean, default: true, null: false
      t.column :auto_subscribe_teams, :boolean, default: true, null: false
    end
  end
end
