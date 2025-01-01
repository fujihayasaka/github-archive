class AddLastUsedAtToSmsRegistrations < ActiveRecord::Migration[7.2]
  def change
    add_column :sms_registrations, :last_used_at, :datetime, precision: nil, null: true
  end
end
