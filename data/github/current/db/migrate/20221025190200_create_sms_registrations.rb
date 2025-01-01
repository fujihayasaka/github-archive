# typed: true

class CreateSmsRegistrations < ActiveRecord::Migration[7.1]
  def change
    create_table :sms_registrations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :user, foreign_key: false, index: true, null: false, type: :bigint, unsigned: true
      t.column :sms_number, "varchar(255)", null: false
      t.column :sms_provider, "varchar(255)", null: true
      t.column :encrypted_otp_secret, "varchar(255)", null: true
      t.column :is_primary, "tinyint(1)", null: false, default: 0
      t.timestamps null: false
    end
  end
end
