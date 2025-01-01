# typed: true

class ChangeIsPasskeyRegistrationToBoolean < ActiveRecord::Migration[7.1]
  def up
    change_column :u2f_registrations, :is_passkey_registration, :boolean, null: false, default: false
  end

  def down
    change_column :u2f_registrations, :is_passkey_registration, :tinyint, limit: 1, null: false, default: 0
  end
end
