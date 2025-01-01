# typed: true

class AddUniquenessConstraintSmsNumber < ActiveRecord::Migration[7.1]
  def change
    add_index :sms_registrations, [:sms_number, :user_id], unique: true
  end
end
