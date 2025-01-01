# typed: true
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

class DropTwoFactorPreferenceAuthenticatedDevices < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersBallast)

  def up
    remove_column :authenticated_devices, :two_factor_preference
  end

  def down
    add_column :authenticated_devices, :two_factor_preference, "tinyint(4) unsigned", null: true
  end
end
