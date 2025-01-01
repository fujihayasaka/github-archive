class AddExpiresAtToUserSessions < ActiveRecord::Migration[7.1]
  def change
    add_column :user_sessions, :expires_at, :datetime, precision: 6, null: true
  end
end
