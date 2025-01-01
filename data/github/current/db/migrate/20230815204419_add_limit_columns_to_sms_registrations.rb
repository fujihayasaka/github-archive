# typed: true
class AddLimitColumnsToSmsRegistrations < ActiveRecord::Migration[7.1]
  def change
    change_table :sms_registrations, bulk: true do |t|
      t.column :consecutive_missed_otp_count, "tinyint(4)", unsigned: true, default: 0, null: false
      t.column :total_otp_sent_count, :int, unsigned: true, default: 0, null: false
      t.column :total_otp_success_count, :int, unsigned: true, default: 0, null: false
      t.column :last_otp_sent_at, :datetime, precision: nil, null: true
      t.column :last_otp_success_at, :datetime, precision: nil, null: true
    end
  end
end
