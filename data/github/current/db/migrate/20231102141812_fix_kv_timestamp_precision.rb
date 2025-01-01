class FixKvTimestampPrecision < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::KeyValues)

  def up
    change_table :key_values, bulk: true do |t|
      t.change :created_at, :datetime, null: false, precision: 6
      t.change :updated_at, :datetime, null: false, precision: 6
      t.change :expires_at, :datetime, null: true, default: nil, precision: 6
    end
  end

  def down
    change_table :key_values, bulk: true do |t|
      t.change :created_at, :datetime, null: false, precision: 0
      t.change :updated_at, :datetime, null: false, precision: 0
      t.change :expires_at, :datetime, null: true, default: nil, precision: 0
    end
  end
end
