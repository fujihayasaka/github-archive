# typed: true

class RemoveDirectMentionMobilePushFromNotificationUserSettings < ActiveRecord::Migration[8.1]

  self.use_connection_class ApplicationRecord::Domain::Notifications

  def change
    remove_column :notification_user_settings, :direct_mention_mobile_push
  end
end
