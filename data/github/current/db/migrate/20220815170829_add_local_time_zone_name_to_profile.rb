# typed: true

class AddLocalTimeZoneNameToProfile < ActiveRecord::Migration[7.1]
  def up
    change_table :profiles, bulk: true do |t|
      # Name and size match mobile_time_zone_name; size supports longest timezone name
      # (ActiveSupport::TimeZone.all.map(&:to_s).map(&:length).max)
      t.column :local_time_zone_name, :string, null: true, limit: 40

      # changes requested by convention:GitHub/ExistingIdColumnsMustBeBigint 👮‍♀️
      t.change :user_id, :bigint, unsigned: true
      t.change :id, :bigint, unsigned: true
    end
  end

  def down
    change_table :profiles, bulk: true do |t|
      t.remove :local_time_zone_name
      t.change :user_id, :int, unsigned: false
      t.change :id, :int, unsigned: false
    end
  end
end
