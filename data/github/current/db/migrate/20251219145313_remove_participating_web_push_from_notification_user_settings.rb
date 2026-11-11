# typed: true

class RemoveParticipatingWebPushFromNotificationUserSettings < ActiveRecord::Migration[8.1]
  self.use_connection_class ApplicationRecord::Domain::Notifications

  def change
    remove_column :notification_user_settings, :participating_web_push, :boolean, default: false, null: false
  end
end
