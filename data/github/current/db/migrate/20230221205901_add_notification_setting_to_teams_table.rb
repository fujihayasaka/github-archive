# typed: true

class AddNotificationSettingToTeamsTable < ActiveRecord::Migration[7.1]
  def change
    add_column(:teams, :notification_setting, :tinyint, default: 0, null: false)
  end
end
