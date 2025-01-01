# typed: true

class AddSaltVersionToTotpAppRegistrations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_column :totp_app_registrations, :salt_version, :tinyint, default: 1, null: false
  end
end
