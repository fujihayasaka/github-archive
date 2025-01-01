# typed: true
class CreateTotpAppRegistrations < ActiveRecord::Migration[7.1]
  def change
    create_table :totp_app_registrations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :user, foreign_key: false, index: true, null: false, type: :bigint, unsigned: true
      t.column :encrypted_otp_secret, "varchar(255)", null: false
      t.timestamps null: false
    end
  end
end
