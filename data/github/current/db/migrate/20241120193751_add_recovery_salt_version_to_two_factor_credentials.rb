# typed: true

class AddRecoverySaltVersionToTwoFactorCredentials < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_column :two_factor_credentials, :recovery_salt_version, :tinyint, default: 1, null: false
  end
end
