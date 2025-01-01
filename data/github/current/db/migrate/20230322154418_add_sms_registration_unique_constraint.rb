# typed: true
class AddSmsRegistrationUniqueConstraint < ActiveRecord::Migration[7.1]
  def up
    change_table :sms_registrations, bulk: true do |t|
      t.remove_index [:user_id]
      t.index [:user_id, :is_primary], unique: true
    end
  end

  def down
    change_table :sms_registrations, bulk: true do |t|
      t.remove_index [:user_id, :is_primary]
      t.index [:user_id], unique: false
    end
  end
end
