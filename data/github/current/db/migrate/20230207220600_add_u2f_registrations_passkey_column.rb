# typed: true

class AddU2fRegistrationsPasskeyColumn < ActiveRecord::Migration[7.1]
  def change
    add_column :u2f_registrations, :is_passkey_registration, :tinyint, limit: 1, null: false, default: 0
  end
end
