# typed: true

class DropU2fRegistrationsTrustedDeviceColumn < ActiveRecord::Migration[7.1]
  def up
    remove_column :u2f_registrations, :trusted_device
  end

  def down
    add_column :u2f_registrations, :trusted_device, "tinyint(1)", null: false, default: 0
  end
end
