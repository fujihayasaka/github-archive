# typed: true

class AddTotpRegistrationUniqueConstraint < ActiveRecord::Migration[7.1]
  def up
    change_table :totp_app_registrations, bulk: true do |t|
      t.remove_index [:user_id]
      t.index [:user_id], unique: true
    end
  end

  def down
    change_table :totp_app_registrations, bulk: true do |t|
      t.remove_index [:user_id]
      t.index [:user_id], unique: false
    end
  end
end
